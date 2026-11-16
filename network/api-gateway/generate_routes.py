#!/usr/bin/env python3
"""Regenerates ROUTES.md from main.tf.

ROUTES.md is derived, not hand-maintained - it's parsed straight out of the
actual aws_apigatewayv2_route resources, so it can't say anything different
from what Terraform will actually deploy. If a route's method, path, or
authorization_type changes in main.tf, this script picks it up automatically
next time it's run - there's nothing to remember to update by hand.

Run after any change to main.tf's routes:
    python3 generate_routes.py
"""

import re
from pathlib import Path

HERE = Path(__file__).parent
MAIN_TF = HERE / "main.tf"
ROUTES_MD = HERE / "ROUTES.md"

# Splits main.tf into one chunk per "# --- <kebab-name> ---" section (the
# target Lambda), then each section into its aws_apigatewayv2_route resources,
# so a route's route_key / authorization_type are only ever read from its own
# resource, not cross-matched with a neighboring one.
SECTION_RE = re.compile(r"# --- (?P<name>[a-z0-9-]+) ---\n(?P<body>.*?)(?=\n# --- |\Z)", re.DOTALL)
ROUTE_RESOURCE_RE = re.compile(r'resource\s+"aws_apigatewayv2_route"\s+"\w+"\s*\{')
ROUTE_KEY_RE = re.compile(r'route_key\s*=\s*"([A-Z]+) (\S+)"')
AUTH_RE = re.compile(r'authorization_type\s*=\s*"(\w+)"')
# The local a for_each iterates, e.g. for_each = toset(local.manage_menu_methods).
FOR_EACH_LOCAL_RE = re.compile(r'for_each\s*=.*?local\.(\w+)')
# A for_each route whose method comes from a `locals { <x>_methods = [...] }`
# list, e.g. route_key = "${each.value} /users/{proxy+}".
FOREACH_ROUTE_KEY_RE = re.compile(r'route_key\s*=\s*"\$\{each\.value\}\s+(\S+)"')
# A for_each route over a list of full route keys, e.g.
#   locals { platform_tenants_routes = ["GET /platform/tenants", ...] }
#   route_key = each.value
# or over an inline toset([...]) of them.
EACH_VALUE_ROUTE_KEY_RE = re.compile(r'route_key\s*=\s*each\.value\b')
TOSET_RE = re.compile(r'toset\(\[(?P<items>[^\]]*)\]\)')
# A for_each over a map of "METHOD /path" = "AUTH" (route_key = each.key,
# authorization_type = each.value), e.g. locals { get_reservation_routes = {...} }.
EACH_KEY_ROUTE_KEY_RE = re.compile(r'route_key\s*=\s*each\.key\b')
EACH_VALUE_AUTH_RE = re.compile(r'authorization_type\s*=\s*each\.value\b')
# Routes behind the operator-pool authorizer (/platform/*) are labelled
# differently from tenant-pool JWT routes.
PLATFORM_AUTHORIZER_RE = re.compile(r'authorizer_id\s*=\s*aws_apigatewayv2_authorizer\.platform\.id')
# Run 0 feature route files (<feature-id>-routes.tf, created by
# feature-routes.tf): entries { route_key = "METHOD /path", auth = "..." }.
FEATURE_ENTRY_RE = re.compile(r'\{[^{}]*\}')
FEATURE_KEY_RE = re.compile(r'route_key\s*=\s*"([A-Z]+) (\S+)"')
FEATURE_AUTH_RE = re.compile(r'\bauth\s*=\s*"(\w+)"')
FEATURE_AUTH_LABELS = {"jwt": "JWT", "public": "NONE", "operator": "JWT (operator)"}


def route_blocks(body):
    """Each aws_apigatewayv2_route resource in a section, braces matched."""
    for m in ROUTE_RESOURCE_RE.finditer(body):
        depth, i = 1, m.end()
        while depth and i < len(body):
            depth += {"{": 1, "}": -1}.get(body[i], 0)
            i += 1
        yield body[m.start():i]


def local_items(text, name, opener):
    """The inside of `name = [ ... ]` or `name = { ... }` (a map closes on its own
    line: its keys hold {locationId}), comments removed; None when not found."""
    if opener == "[":
        m = re.search(rf'\b{name}\s*=\s*\[(?P<items>[^\]]*)\]', text)
    else:
        m = re.search(rf'\b{name}\s*=\s*\{{(?P<items>.*?)\n\s*\}}', text, re.DOTALL)
    return re.sub(r"#[^\n]*", "", m.group("items")) if m else None


def parse_routes():
    # Feature files whose sections use the same "# --- <kebab-name> ---"
    # markers (e.g. printing-routes.tf) are read after main.tf, each on its own.
    files = [MAIN_TF, *sorted(p for p in HERE.glob("*-routes.tf") if "# --- " in p.read_text())]
    routes = []
    for f in files:
        text = f.read_text()
        for m in SECTION_RE.finditer(text):
            name = m.group("name")
            body = m.group("body")
            # authorization_type is read per route resource: one section can
            # hold a public route next to a JWT one (e.g. get-menu).
            for block in route_blocks(body):
                for method, path, auth in block_routes(block, body, text):
                    if auth == "JWT" and PLATFORM_AUTHORIZER_RE.search(block):
                        auth = "JWT (operator)"
                    routes.append({"lambda": name, "method": method, "path": path, "auth": auth})

    # Feature route files have no section markers; operator routes are
    # served by platform-tenants, which forwards to the feature.
    for f in sorted(HERE.glob("*-routes.tf")):
        text = f.read_text()
        if "# --- " in text:
            continue
        text = re.sub(r"#.*", "", text)  # the stubs' comments show an example entry
        for entry in FEATURE_ENTRY_RE.findall(text):
            key, auth = FEATURE_KEY_RE.search(entry), FEATURE_AUTH_RE.search(entry)
            if not (key and auth):
                continue
            feature = f.name[: -len("-routes.tf")]
            routes.append({
                "lambda": "platform-tenants" if auth.group(1) == "operator" else feature,
                "method": key.group(1),
                "path": key.group(2),
                "auth": FEATURE_AUTH_LABELS[auth.group(1)],
            })
    return routes


def block_routes(block, body, text):
    """(method, path, auth) for each route one resource creates. A local the
    for_each names is looked up in the section first, then in the file."""
    local = FOR_EACH_LOCAL_RE.search(block)
    local = local.group(1) if local else None

    def items(opener):
        if not local:
            return None
        found = local_items(body, local, opener)
        return found if found is not None else local_items(text, local, opener)

    # Map of "METHOD /path" = "AUTH": the auth comes with each key.
    if EACH_KEY_ROUTE_KEY_RE.search(block) and EACH_VALUE_AUTH_RE.search(block):
        pairs = items("{") or ""
        return re.findall(r'"([A-Z]+) (\S+)"\s*=\s*"(\w+)"', pairs)

    auth_match = AUTH_RE.search(block)
    if not auth_match:
        return []  # an auth this script can't resolve: no row rather than a wrong one
    auth = auth_match.group(1)

    # A literal route_key.
    keys = ROUTE_KEY_RE.findall(block)
    if keys:
        return [(method, path, auth) for method, path in keys]

    # for_each over an inline toset([...]) of complete "METHOD /path" keys
    # (a named local wins: `cond ? toset(local.x) : toset([])` lists local.x).
    toset_match = TOSET_RE.search(block)
    if toset_match and not local and EACH_VALUE_ROUTE_KEY_RE.search(block):
        return [(method, path, auth) for method, path in re.findall(r'"([A-Z]+) (\S+)"', toset_match.group("items"))]

    # for_each over a methods list: route_key = "${each.value} /path".
    foreach_match = FOREACH_ROUTE_KEY_RE.search(block)
    if foreach_match:
        methods = re.findall(r'"([A-Z]+)"', items("[") or "")
        return [(method, foreach_match.group(1), auth) for method in methods]

    # for_each over a list of complete "METHOD /path" keys.
    if EACH_VALUE_ROUTE_KEY_RE.search(block):
        return [(method, path, auth) for method, path in re.findall(r'"([A-Z]+) (\S+)"', items("[") or "")]

    return []  # no shape matched


def render_markdown(routes):
    lines = [
        "<!-- GENERATED FILE - do not hand-edit. Run `python3 generate_routes.py` -->",
        "<!-- after changing routes in main.tf to bring this back in sync.        -->",
        "",
        "# HTTP API routes",
        "",
        "One row per route defined in `main.tf`. `Auth` is `NONE` (no token required),",
        "`JWT` (a valid access token from the TENANT user pool in the `Authorization`",
        "header, validated by the `cognito` authorizer; the Lambda then checks the",
        "token's tenant_id against the resource) or `JWT (operator)` (an access token",
        "from the OPERATOR user pool with the `platform/admin` scope, validated by the",
        "`platform` authorizer).",
        "",
        "| Method | Path | Auth | Lambda |",
        "|---|---|---|---|",
    ]
    for r in routes:
        lines.append(f"| {r['method']} | `{r['path']}` | {r['auth']} | {r['lambda']} |")
    lines.append("")
    return "\n".join(lines)


def main():
    routes = parse_routes()
    ROUTES_MD.write_text(render_markdown(routes), newline="\n")
    print(f"wrote {len(routes)} routes to {ROUTES_MD}")


if __name__ == "__main__":
    main()
