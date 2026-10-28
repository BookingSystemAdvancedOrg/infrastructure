# Customer sites: runbook

Every restaurant has its own private website repo `site-<slug>` in
BookingSystemAdvancedOrg, designed in Figma by Booqy and coded with Claude
on top of `@bookingsystemadvancedorg/site-kit`. Every site is live on its
slug address from the first deploy (`<slug>.booqy.se`, dev
`<slug>.dev.booqy.se`); the restaurant's own domain is added when it is
ready and never blocks a deploy (owner's decision 2026-10-28). Plan and
decisions:
`application/docs/orchestrator/CUSTOMER-SITES-PLAN.md`.

```
prod console "New customer" ──> site-repo (prod) ──> repo site-<slug> from site-template (the only place a repo is born)
                                                    booqy.json (prod), PROD_* variables, role /booqy-sites/site-<slug> (main only)
                                  └─ assume dev booqy-sites-prod-link ──> dev platform-tenants (site task)
                                       ──> empty dev tenant, same slug ──> dev onboarding ──> site-repo (dev):
                                           <slug>.dev.booqy.se, booqy.json (dev), DEV_* variables,
                                           role /booqy-sites/dev-site-<slug> (dev only), first deploy
                                  └─ first prod deploy of main ──> <slug>.booqy.se
push to dev       ──> Deploy ──> dev account  sites/<devTenantId>/ ──> <slug>.dev.booqy.se (noindex)
merge dev -> main ──> Deploy ──> prod sites/<tenantId>/ ──> <slug>.booqy.se (+ www.restaurant.se once mounted)
Website tab "Mount" ──> prod: domain-attach www.<domain>   dev (link): domain-attach dev.<domain>
dev console "New customer" ──> dry run only (shows what prod would create); slugs test-* are real (testing)
```

| Piece | Where |
|---|---|
| Repos | `site-kit` (the package), `site-template`, `site-<slug>` (one per restaurant), all private |
| Package | `@bookingsystemadvancedorg/site-kit` on GitHub Packages (GitHub only accepts the owner's name as scope) |
| Sites bucket | `<env->restaurant-sites-<account>`, folder `sites/<tenantId>/`, versioned (30 days) |
| Serving | multi-tenant distribution, origin `tenant-site` with origin path `/sites/{{tenantId}}` (when `per_tenant_sites = true`) |
| Function | `site-repo` (application `functions/site-repo`), called by onboarding, offboarding and the console |
| Deploy roles | `/booqy-sites/<env->site-<slug>`, one per customer per account, created at runtime |
| Console | customer page, tab **Website** |

Restaurant data is never copied between environments: the dev tenant starts
empty, and the restaurant and developers enter test data in the dev admin
app; real data goes into prod's admin app.

GitHub plan Free: no deployment approvals in private repos, so the deploy
workflow picks repo-level `DEV_*` / `PROD_*` variables by branch, and each
deploy role's OIDC trust allows only its branch (dev role: `dev`, prod role:
`main`). No approval button before prod: a merge to `main` is the release.

**Addresses.** Sites are served by each account's one multi-tenant
CloudFront distribution, which has no `*.cloudfront.net` address per site:
a site is reached only by a hostname on it. So every restaurant gets a
platform hostname at onboarding (`<slug>.booqy.se` in prod, since
2026-10-28; `<slug>.dev.booqy.se` in dev), and its own domain is a second
hostname on the same site. One hostname can be on only one CloudFront
distribution in the world, so production gets `www.<domain>` (and the apex
when Booqy runs the DNS) and dev gets `dev.<domain>`.

**Caveat:** while `per_tenant_sites` is off in an environment (prod today),
every hostname there serves the shared customer-front-end build, not the
repo's site: prod deploys succeed and land in `sites/<tenantId>/`, and show
on the addresses once `per_tenant_sites = true` in `prod.tfvars`.

---

## One-time setup (owner)

### 1. Register the GitHub App "Booqy Sites"

Open this link (signed in as an org owner); every setting is filled in:

<https://github.com/organizations/BookingSystemAdvancedOrg/settings/apps/new?name=Booqy%20Sites&description=Creates%20and%20manages%20the%20restaurant%20site%20repos%20(site-*)%20for%20Booqy&url=https%3A%2F%2Fbooqy.se&public=false&webhook_active=false&administration=write&contents=write&actions=write&variables=write&workflows=write&metadata=read>

Check before **Create GitHub App**:

- Webhook: Active **unticked**.
- Repository permissions: Administration, Contents, Actions, Variables and
  Workflows **Read and write**; Metadata Read. Nothing else, no
  organization or account permissions.
- Where can it be installed: **Only on this account**.

Then on the App page: note the **App ID**; **Generate a private key** (a
`.pem` downloads). Never paste it anywhere else, commit it or send it in chat.

### 2. Install it on the site repos only

App page -> **Install App** -> BookingSystemAdvancedOrg -> **Only select
repositories** -> `site-kit` and `site-template` (plus any existing
`site-*`). Never "All repositories", never a platform repo. Repos the App
creates later are added to the installation by GitHub automatically.

### 3. Store the key in both accounts

Same key, two secrets: `booqy/dev/github-app-sites` in the **dev** account
(877653167825) and `booqy/prod/github-app-sites` in the **prod** account
(343695380960), region eu-north-1. Easiest from AWS CloudShell, so the key
never touches a terminal history or the screen:

1. AWS console, dev account, region Stockholm (eu-north-1) -> CloudShell.
2. Actions -> Upload file -> the `.pem`.
3. Run (put in the App ID):

```bash
jq -n --arg id "<App ID>" --rawfile key ~/*.private-key.pem '{app_id:$id, private_key:$key}' > ~/gh-app.json && aws secretsmanager create-secret --region eu-north-1 --name booqy/dev/github-app-sites --description "Booqy Sites GitHub App (site-repo)" --secret-string file://$HOME/gh-app.json && rm ~/gh-app.json ~/*.private-key.pem
```

4. The same in the prod account, with the name `booqy/prod/github-app-sites`:

```bash
jq -n --arg id "<App ID>" --rawfile key ~/*.private-key.pem '{app_id:$id, private_key:$key}' > ~/gh-app.json && aws secretsmanager create-secret --region eu-north-1 --name booqy/prod/github-app-sites --description "Booqy Sites GitHub App (site-repo)" --secret-string file://$HOME/gh-app.json && rm ~/gh-app.json ~/*.private-key.pem
```

5. Delete the downloaded `.pem` from your computer.

Only the `site-repo` role of each account can read its secret. Rotate
yearly: generate a new key on the App page, `put-secret-value` in both
accounts, delete the old key on the App page.

### 4. Let the site repos read the kit

GitHub Packages has no API for this, so it is a setting on the package
(Organization -> Packages -> `site-kit` -> Package settings):

- **Recommended: Change visibility -> Public.** Every repo's Actions,
  Dependabot and every developer with any GitHub token can install it; no
  click per new restaurant. The code is the same as in the public
  customer-front-end repo, so nothing new is exposed. (Org setting
  "Package creation: Public" must be allowed.)
- Or keep it private: **Manage Actions access -> Add repository** for
  `site-template` and for **every new** `site-<slug>` (Role: Read), and give
  every outside developer read access to `site-kit`. A new site's first
  deploy fails until that click is done.

Then: site-template -> Actions -> **Lockfile** -> Run workflow on `dev`
(writes `package-lock.json`), and merge `dev` into `main` in site-template.

### 5. Switch it on

`dev.tfvars` and `prod.tfvars`: uncomment `github_app_sites_secret_name`;
push dev (prod follows with the merge to main). Prod onboarding creates
repos only once prod has it and the link (`site_link_dev_account_id`, set).
Until then the dev console shows a dry run for new customers; slugs starting
with `test-` create real `site-test-<slug>` repos from dev, for testing.

When every active restaurant with a domain in an environment has a deployed
site, uncomment `per_tenant_sites = true` there so domains serve their own
site instead of the shared customer-front-end build.

---

## Per customer

1. Booqy designs the site in Figma (duplicated from "Booqy site - start").
2. **Prod** console -> **New customer** (the slug becomes the repo name
   `site-<slug>`).
3. Prod onboarding creates the restaurant, then the repo from
   `site-template` (branches `dev` and `main`, default `dev`), the prod
   deploy role, the `PROD_*` variables and `booqy.json`'s prod section.
4. Through the link role it creates the same restaurant, empty, in dev
   (same slug; an existing dev customer with that slug is reused). The owner
   gets a dev admin invitation too.
   The dev invitation goes to the owner's address; when that address
   already signs in to another dev customer, to `<local>+<slug>@<domain>`
   (same mailbox with most providers).
5. Dev onboarding of that tenant: `<slug>.dev.booqy.se`, the dev deploy
   role, `DEV_*` variables, `booqy.json`'s dev section, first deploy. Prod
   deploys `main` once (live on `<slug>.booqy.se`). A few minutes in all.
6. Prod console -> Website: status **Ready**, Dev **Live**, Production
   **Live**; "Where the site answers" lists both slug addresses as
   **Slug address only**. The dev console shows the same repo read-only.
7. The restaurant and the developer enter test data in the **dev** admin.
8. **Give access** (prod console) to the developer's GitHub username: write
   on this repo only.
9. The developer: **Get started locally** (clone, `npm install`, `npm run dev`).
10. Code the design on `dev` with Claude and the kit's components.
11. Every push to `dev` deploys to `https://<slug>.dev.booqy.se`; the
    restaurant reviews it there and approves.
12. Meanwhile the restaurant enters its real menu and settings in the prod admin.
13. Whenever the restaurant is ready (never needed for a deploy): prod
    console -> Domains: buy or connect the restaurant's domain (or a bare
    CNAME); wait for **Live** (certificate issued). That already mounts it
    on production (`<domain>` and `www.<domain>`).
14. Prod console -> Website -> "Where the site answers": Production shows
    **Live** on `www.<domain>` (**Mount** / **Retry** if it is missing or
    failed). Dev: **Mount dev.<domain>** runs dev's domain-attach through
    the link. When Booqy runs the domain's DNS (bought or connected) the
    console writes the `dev.<domain>` CNAME itself; with a bare CNAME the
    restaurant adds **one more record**, `dev.<domain>` CNAME to the dev
    target the tab shows. Dev shows **Waiting for DNS**, **Issuing
    certificate**, then **Live**; **Failed** has **Retry**. The slug
    addresses keep working.
15. Prod console -> Website -> **Run setup again** (writes the domain into
    `booqy.json`, so the dev preview's canonical link names it).
16. PR `dev` -> `main` in the site repo, review, merge: deploys to the prod
    account, live on the slug address and the own domain.
17. Check the site on each address: booking, order, catering.
18. Kit updates arrive as Dependabot PRs to `dev` from now on.

### Deploys and rollback

- `dev` -> dev account, `main` -> prod account. A prod deploy needs the
  restaurant to be active in prod (site-config answers 200); an own domain
  is optional (until 2026-10-28 it was required, and every first prod
  deploy failed). Repos generated before that keep the old gate in their
  own `deploy.yml` until it is updated the same way as site-template's.
- index.html is uploaded no-cache, hashed files immutable: no CloudFront
  invalidation.
- **Rollback**: site repo -> Actions -> Deploy -> Run workflow on the
  branch, `sha` = an older commit on it. Or the console's **Redeploy** for
  the branch head. The bucket also keeps the previous build 30 days.
- Every deploy first tries to write into another folder and must be
  refused (Isolation check); a deploy whose role could write elsewhere stops.

### Kit updates

Dependabot opens a PR to `dev` for every new `site-kit` version. A patch
version is merged and deployed to dev by CI once green; minor and major wait
for a person. Releasing the kit: `site-kit/README.md`, Release.

### Offboarding

Offboarding a customer in **prod** (Danger zone) also runs `site-repo
archive`: the prod deploy role and `PROD_*` variables are removed, prod asks
dev (link role) to remove the dev role and `DEV_*` variables, then the repo
is archived (read-only, never deleted). The dev tenant stays as test data;
offboard it in the dev console if wanted. Offboarding in dev removes only
the dev side.
The Website tab has the same as **Archive**. **Set up** (or onboarding in
the other environment) unarchives it. The site's files stay in
`sites/<tenantId>/`; the domain is detached by offboarding, so nothing
serves them.

---

## IAM

Owner-approved 2026-10-27. Nothing here touches the platform's own OIDC
roles (`dev-infra-oidc-role`, the front-end and back-end deploy roles).

- `/booqy-sites/<env->booqy-sites-deploy-boundary` (Terraform, `sites/`,
  each account): permissions boundary; S3 Put/Get/Delete on
  `sites/${aws:PrincipalTag/tenantId}/*` and ListBucket with that prefix, in
  that account's sites bucket only.
- `/booqy-sites/site-<slug>` (prod account) and
  `/booqy-sites/dev-site-<slug>` (dev account), created by each account's
  own `site-repo`: that boundary, tag `tenantId`, inline policy
  `deploy-own-site` with the same rights for its literal tenant. Trust: the
  account's existing GitHub OIDC provider, audience `sts.amazonaws.com`,
  subject exactly
  `repo:BookingSystemAdvancedOrg@<org id>/site-<slug>@<repo id>:ref:refs/heads/main`
  (prod) or `...:ref:refs/heads/dev` (dev): GitHub's default subject, which
  in this organisation is the immutable one (ids in it), so a deleted and
  re-created repo with the same name can't use the role. A site repo's
  token has the same `repo:BookingSystemAdvancedOrg@...` shape as every
  other repo's: **any platform role that trusts the whole organisation
  (`repo:BookingSystemAdvancedOrg@*/*`) is reachable from a site repo**, and
  outside developers get write access to site repos. Every platform role
  must trust only its own repo (check `dev-infra-oidc-role` and
  `prod-infra-oidc-role`).
- `<env->site-repo-role` (Terraform, each account): CreateRole and
  PutRolePolicy only on `role/booqy-sites/*` and only with the boundary;
  Get/Tag/UpdateAssumeRolePolicy/ListRolePolicies/DeleteRolePolicy/
  DeleteRole/SimulatePrincipalPolicy on `role/booqy-sites/*`; explicit Deny
  on removing or swapping the boundary and on AttachRolePolicy; tenant table
  Get/Put/UpdateItem; the App secret. Prod only: `sts:AssumeRole` on
  `arn:aws:iam::877653167825:role/booqy-sites-prod-link`.
- `booqy-sites-prod-link` (Terraform, **dev account only**), the prod ->
  dev link:

  ```json
  Trust: {"Effect": "Allow", "Principal": {"AWS": "arn:aws:iam::343695380960:root"},
          "Action": "sts:AssumeRole",
          "Condition": {"ArnEquals": {"aws:PrincipalArn": "arn:aws:iam::343695380960:role/site-repo-role"}}}
  Policy: {"Sid": "SiteTaskOnly", "Effect": "Allow", "Action": "lambda:InvokeFunction",
           "Resource": "arn:aws:lambda:eu-north-1:877653167825:function:dev-platform-tenants:live"}
  ```

  dev `platform-tenants` accepts only `{"siteTask": {"action": "mirror" |
  "archive" | "domain", "slug", ...}}` from it, and refuses site tasks in
  prod. Mirror
  creates (through the normal New customer path, no data copied) or adopts
  the dev tenant with that slug; its onboarding creates the dev distribution
  tenant and, through dev `site-repo`, the `/booqy-sites/` role. Archive
  removes that dev side. Dev has no role or right in prod.
- Onboarding and offboarding state machine roles, platform-tenants role:
  `lambda:InvokeFunction` on the `site-repo` live alias.
- Slug addresses: `tenant_subdomains_enabled = true` adds
  `cloudfront:CreateDistributionTenant` / `GetDistributionTenant` (the
  account's multi-tenant distribution only) to the onboarding role, plus
  the `*.<platform domain>` CNAME. Dev since 2026-10-20, prod since
  2026-10-28 (owner-approved). Mounting a domain adds no IAM: prod uses
  platform-tenants' existing domain-attach and restaurant-zone rights; dev
  uses the same link role (site task `domain`, op `status` or `mount`,
  which only runs dev's domain-attach for that slug's dev tenant).

Isolation is checked twice: at setup with the IAM policy simulator
(own folder allowed, another tenant's folder and the bucket root denied;
setup fails otherwise) and on every deploy with a real write that must be
refused.

---

## Troubleshooting

| Symptom | Cause, fix |
|---|---|
| Website tab: "Site repos aren't switched on" | `github_app_sites_secret_name` not set in that environment's tfvars |
| Setup failed: `GitHub POST .../generate: 403` | The App is not installed on `site-template`, or lacks Administration write |
| Setup failed: `refused: ... not a site-* repository name` | Slug not usable as a repo name; never bypass |
| Deploy: `403 Forbidden ... read_package` | The repo can't read the kit: step 4 above |
| Deploy: "No own domain attached and verified" | A repo generated before 2026-10-28 with the old gate: give its `deploy.yml` site-template's "Restaurant is active" step (both branches), then Redeploy main |
| Website tab: slug address "not made yet" | The tenant was onboarded before its environment had slug addresses (prod before 2026-10-28): Domains tab -> **Re-run setup** |
| Website tab: Dev "Unknown" | The prod -> dev link failed (message under it); Refresh |
| Website tab: Dev own domain **Waiting for DNS** | `dev.<domain>` CNAME is missing at the restaurant's DNS provider (bare CNAME domains only) |
| Deploy: "No dev customer for this repo yet" | No `DEV_*` variables: the dev tenant's onboarding hasn't finished; prod Website tab -> Run setup again |
| Setup failed: `dev side: ...` | The prod -> dev link failed (dev API or the dev tenant); the message names the field dev refused. Fix, then Run setup again in prod |
| Dev console: "Dry run" | Expected: repos are born in prod. Use a `test-` slug to test in dev |
| Deploy: Isolation check failed | Stop. The role can write elsewhere: check the role's boundary and policy in IAM |

## End-to-end test (dev)

Use slugs starting with `test-` (repos `site-test-<slug>`): in the dev
console they create real repos (everything else there is a dry run). Create
two, check both deploy and both Isolation checks pass, try a plain slug (dry
run, nothing created), then Archive both test repos on the Website tab.
After the prod merge: one real prod customer to check the prod -> dev link.
