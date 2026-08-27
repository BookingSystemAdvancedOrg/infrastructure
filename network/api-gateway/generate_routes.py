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

# Splits main.tf into one chunk per "# --- <kebab-name> ---" section, so
# each route's route_key / authorization_type / target Lambda are only
# ever read from within their own block, not accidentally cross-matched
# with a neighboring one.
SECTION_RE = re.compile(r"# --- (?P<name>[a-z0-9-]+) ---\n(?P<body>.*?)(?=\n# --- |\Z)", re.DOTALL)
ROUTE_KEY_RE = re.compile(r'route_key\s*=\s*"([A-Z]+) (\S+)"')
# A for_each route whose method comes from a `locals { <x>_methods = [...] }`
# block earlier in the same section, e.g. route_key = "${each.value} /users/{proxy+}".
FOREACH_ROUTE_KEY_RE = re.compile(r'route_key\s*=\s*"\$\{each\.value\}\s+(\S+)"')
METHODS_LIST_RE = re.compile(r'_methods\s*=\s*\[(?P<items>[^\]]*)\]')
AUTH_RE = re.compile(r'authorization_type\s*=\s*"(\w+)"')


def parse_routes():
    text = MAIN_TF.read_text()
    routes = []
    for m in SECTION_RE.finditer(text):
        name = m.group("name")
        body = m.group("body")

        auth_match = AUTH_RE.search(body)
        if not auth_match:
            continue  # not a route section (e.g. trailing content) - skip
        auth = auth_match.group(1)

        route_key_match = ROUTE_KEY_RE.search(body)
        if route_key_match:
            method, path = route_key_match.groups()
            routes.append({"lambda": name, "method": method, "path": path, "auth": auth})
            continue

        # for_each route: one row per method in the section's `*_methods` locals list.
        foreach_match = FOREACH_ROUTE_KEY_RE.search(body)
        methods_match = METHODS_LIST_RE.search(body)
        if foreach_match and methods_match:
            path = foreach_match.group(1)
            methods = re.findall(r'"([A-Z]+)"', methods_match.group("items"))
            for method in methods:
                routes.append({"lambda": name, "method": method, "path": path, "auth": auth})
            continue

        # Neither shape matched - not a route section, skip.
    return routes


def render_markdown(routes):
    lines = [
        "<!-- GENERATED FILE - do not hand-edit. Run `python3 generate_routes.py` -->",
        "<!-- after changing routes in main.tf to bring this back in sync.        -->",
        "",
        "# HTTP API routes",
        "",
        "One row per route defined in `main.tf`. `Auth` is `NONE` (no token required)",
        "or `JWT` (must present a valid Cognito access token in the `Authorization`",
        "header, validated by the `cognito` authorizer).",
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
