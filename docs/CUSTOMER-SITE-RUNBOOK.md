# Customer sites: runbook

Every restaurant has its own public website repo `site-<slug>` in the
GitHub organisation **BooqyCustomers** (since 2026-11-15; only site repos and
`site-template` live there, the platform repos stay in
BookingSystemAdvancedOrg), designed in Figma by Booqy and coded with Claude
on top of `@bookingsystemadvancedorg/site-kit`. Every site is live on its
slug address from the first deploy (`<slug>.booqy.se`, dev
`<slug>.dev.booqy.se`); the restaurant's own domain is added when it is
ready and never blocks a deploy (owner's decision 2026-10-28). Plan and
decisions:
`application/docs/orchestrator/CUSTOMER-SITES-PLAN.md`.

```
prod console "New customer" ──> site-repo (prod) ──> repo site-<slug> from site-template (the only place a repo is born)
                                                    role /booqy-sites/site-<slug> (main only)
                                  └─ assume dev booqy-sites-prod-link ──> dev platform-tenants (site task "mirror", repo named by prod)
                                       ──> the dev twin, same name, slug and plan (owner dev+<slug>@booqy.se, its onboarding:
                                           <slug>.dev.booqy.se), seeded with test data (booqy-console docs/DEV-TWINS.md)
                                       ──> site-repo (dev) linkProvision, AWS only: role /booqy-sites/dev-site-<slug>
                                           (dev branch of that repo id only) ──> answers role ARN, bucket, booqy.json dev values
                                  └─ site-repo (prod), with the Customer Sites key: PROD_* and DEV_* variables,
                                     booqy.json (prod and dev), first deploys ──> <slug>.booqy.se, <slug>.dev.booqy.se
push to dev       ──> Deploy ──> dev account  sites/<devTenantId>/ ──> <slug>.dev.booqy.se (noindex)
merge dev -> main ──> Deploy ──> prod sites/<tenantId>/ ──> <slug>.booqy.se (+ www.restaurant.se once mounted)
Website tab "Mount" ──> prod: domain-attach www.<domain>   dev (link): domain-attach dev.<domain>
dev console "New customer" ──> test customer: repo site-<slug> in BooqyCustomersDev (see "Test sites" below)
```

| Piece | Where |
|---|---|
| Repos | BooqyCustomers: `site-template` (GitHub template) and `site-<slug>` (one per restaurant, public). BookingSystemAdvancedOrg: `site-kit` (the package, public) |
| Org setting | `site_github_org = "BooqyCustomers"` in `dev.tfvars` and `prod.tfvars` (the site-repo function's `GITHUB_ORG`); the platform OIDC trusts keep `github_org` |
| Package | `@bookingsystemadvancedorg/site-kit` on GitHub Packages (GitHub only accepts the owner's name as scope), public so repos in BooqyCustomers can install it |
| Sites bucket | `<env->restaurant-sites-<account>`, folder `sites/<tenantId>/`, versioned (30 days) |
| Serving | multi-tenant distribution, origin `tenant-site` with origin path `/sites/{{tenantId}}` (when `per_tenant_sites = true`) |
| Function | `site-repo` (application `functions/site-repo`), called by onboarding, offboarding and the console |
| Deploy roles | `/booqy-sites/<env->site-<slug>`, one per customer per account, created at runtime |
| Console | customer page, tab **Website** |

**Key isolation (owner 2026-11-15).** Only the **prod** account holds the
"Booqy Customer Sites" key. The dev account holds only the "Booqy Test
Sites" key (BooqyCustomersDev) and never calls GitHub for a repo in
BooqyCustomers: every GitHub write for a real customer (repo, `DEV_*` and
`PROD_*` variables, `booqy.json` for both environments, deploys, archive,
delete) is done by prod's site-repo. Dev does only the AWS side when prod
asks through the link: the dev deploy role, whose trust dev writes only for
a BooqyCustomers repo (login and id 356944191) with the repo id prod
supplies.

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

### 1. The organisation BooqyCustomers and its GitHub App

Done 2026-11-15. The organisation `BooqyCustomers` (id 356944191, plan
Free) holds only `site-template` and the `site-<slug>` repos, so a site
repo's OIDC token (`repo:BooqyCustomers@356944191/...`) can never match a
platform role, which trusts `repo:BookingSystemAdvancedOrg@...`.

The GitHub App **"Booqy Customer Sites"** (slug `booqy-customer-sites`,
App ID 5769537, owned by BooqyCustomers, private, webhook off):

- Repository permissions: Administration, Contents, Actions, Variables and
  Workflows **Read and write**; Metadata Read. Nothing else, no
  organization or account permissions.
- Where can it be installed: **Only on this account**.

It replaces the old "Booqy Sites" App in BookingSystemAdvancedOrg; once the
new key is in both secrets (step 3) and a test repo is created, uninstall
and delete the old App there. Never paste the App's private key anywhere
else, commit it or send it in chat.

### 2. Install it on all repositories, and the org settings

App page -> **Install App** -> BooqyCustomers -> **All repositories**. The
organisation holds only site repos, so "All" is the narrow choice here and
every repo the App generates is covered without a click.

BooqyCustomers settings (Organization -> Settings):

- **Actions -> General -> Policies:** "Allow BooqyCustomers, and select
  non-BooqyCustomers, actions": only `actions/checkout@*`,
  `actions/setup-node@*`, `aws-actions/configure-aws-credentials@*` and
  `dependabot/fetch-metadata@*` (exactly what site-template's workflows use).
- **Actions -> General -> Workflow permissions:** Read repository contents
  and packages permissions (each workflow asks for more where it needs it).
- **Member privileges -> Base permissions:** No permission. Booqy staff are
  owners; nobody else is an org member.
- **Developers:** never org members. **Give access** (prod console, Website
  tab) adds the developer's GitHub username as an outside collaborator with
  write on that one repo.

### 3. Store the keys: one per account

Two Apps, two secrets, one key each (key isolation, 2026-11-15):

| Account | Secret | Holds |
|---|---|---|
| prod (343695380960) | `booqy/prod/github-app-sites` | "Booqy Customer Sites" (App ID 5769537, BooqyCustomers) |
| dev (877653167825) | `booqy/dev/github-app-sites` | "Booqy Test Sites" (App ID 5770798, BooqyCustomersDev), done by the owner 2026-11-15 |

The Customer Sites key is never stored in dev. Easiest from AWS CloudShell
in the right account (region eu-north-1), so a key never touches a terminal
history or the screen: Actions -> Upload file -> the `.pem`, then (App ID
and secret id of that account):

```bash
jq -n --arg id "<App ID>" --rawfile key ~/*.private-key.pem '{app_id:$id, private_key:$key}' > ~/gh-app.json && aws secretsmanager put-secret-value --region eu-north-1 --secret-id <secret id> --secret-string file://$HOME/gh-app.json && rm ~/gh-app.json ~/*.private-key.pem
```

Delete the downloaded `.pem` from your computer afterwards. A warm function
keeps its App token up to 50 minutes; every cold start reads the secret
again.

Only the `site-repo` role of each account can read its secret. Rotate
yearly: generate a new key on the App page, `put-secret-value` in that
account, delete the old key on the App page.

### 4. Let the site repos read the kit

GitHub Packages has no API for this, so it is a setting on the package
(Organization -> Packages -> `site-kit` -> Package settings):

- **Required since the site repos moved to BooqyCustomers: Public** (an
  Actions access grant only reaches repos in the package's own
  organisation). **Change visibility -> Public.** Every repo's Actions,
  Dependabot and every developer with any GitHub token can install it; no
  click per new restaurant. The code is the same as in the public
  customer-front-end repo, so nothing new is exposed. (Org setting
  "Package creation: Public" must be allowed.)
- (Before the move it could stay private with **Manage Actions access**
  per repo; that no longer works across organisations.)

Then: site-template -> Actions -> **Lockfile** -> Run workflow on `dev`
(writes `package-lock.json`), and merge `dev` into `main` in site-template.

### 5. Switch it on

`dev.tfvars` and `prod.tfvars`: uncomment `github_app_sites_secret_name`
and set `site_github_org = "BooqyCustomers"` (both done);
push dev (prod follows with the merge to main). Prod onboarding creates
repos only once prod has it and the link (`site_link_dev_account_id`, set).
Customers created in the dev console are test customers ("Test sites"
below); dev never creates a repo in BooqyCustomers.

**Order of the key isolation rollout:** dev gets the new code first (dev
then stops writing to BooqyCustomers); a real customer's dev side set up
before keeps working (its `DEV_*` variables and dev role stay as they
are, for example `site-test-release`). A new prod customer gets its dev
side once prod has the new code too (owner's merge to main): then prod
console -> Website -> **Run setup again** for any prod customer created in
between.

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
5. In the same step dev writes the dev deploy role (AWS only, for the repo
   id prod names) and answers with its values; prod writes the `DEV_*`
   variables and `booqy.json`'s dev section (that commit deploys `dev`) and
   deploys `main` once (live on `<slug>.booqy.se`). Dev onboarding of the
   tenant makes `<slug>.dev.booqy.se`. A few minutes in all.
6. Prod console -> Website: status **Ready**, Dev **Live**, Production
   **Live**; "Where the site answers" lists both slug addresses as
   **Slug address only**. The dev console shows the repo as managed from
   prod (no deploys there: dev can't read BooqyCustomers).
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
archive`: the prod deploy role is removed, prod asks dev (link role) to
remove the dev role, prod removes the `PROD_*` and `DEV_*` variables, then
the repo is archived (read-only). The dev tenant stays as test data;
offboard it in the dev console if wanted. Offboarding in dev removes only
the dev role (dev makes no GitHub call): the `DEV_*` variables stay until
prod's Run setup again (which writes a new role) or prod's archive.
The Website tab has the same as **Archive**. **Set up** (or onboarding in
the other environment) unarchives it. The site's files stay in
`sites/<tenantId>/`; the domain is detached by offboarding, so nothing
serves them.

**Restore customer** (Danger zone, until `purgeAt`) re-runs onboarding:
the slug address comes back and `site-repo provision` unarchives the repo
and sets up the deploy role and variables again; in prod the link restores
the offboarded dev tenant the same way. Own domains are re-added by hand.

**Delete customer** (Danger zone, offboarded customers only) and the
automatic purge after the retention period run `site-repo delete`: archive
first (prod also asks dev to drop its side), then `DELETE /repos/...` once
no `*_TENANT_ID` variable is left. A real customer's repo is deleted only by
prod; dev's purge of its dev tenant removes only the dev role. Dev deletes
its test customers' repos in BooqyCustomersDev. Older `site-test-*` repos dev
made alone in BooqyCustomers before key isolation are deleted by hand.
The result goes to the activity log (`site_repo_deleted`,
`site_repo_not_deleted` or `site_repo_delete_failed`) and, at the purge, to
the summary email. A refusal never stops the data deletion; delete the
archived repo by hand on GitHub then. Afterwards the slug is free: **New
customer** with it takes over the purged customer's `SLUG#` claim and
onboarding generates a fresh repo from `site-template` (new repo id, so
the old deploy role's OIDC subject can't match it).

---

## Test sites (dev console)

Owner decision 2026-11-15. Every customer created in the **dev** console is
a test customer (PROFILE `siteKind: "test"`, set by dev platform-tenants
once `test_sites_enabled`): a real, public repo `site-<slug>` in the GitHub
org **BooqyCustomersDev** (id 356983507, App "Booqy Test Sites", App ID
5770798, installed on all repositories), generated from the public
`BooqyCustomers/site-template` (`site_template_owner`). Both branches deploy
in the **dev account** to the test sites sandbox (`test-sites.tf`), never to
the real customers' dev sites on `dev.booqy.se`:

```
dev console "New customer" ──> dev onboarding ──> claims <slug>.test.booqy.se (main) + <slug>.test-dev.booqy.se (dev),
                                                  then site-repo (dev, test mode): host map <slug> -> tenantId,
                                                  repo BooqyCustomersDev/site-<slug>, roles
                                                  /booqy-test-sites/test-site-<slug>-main and -dev,
                                                  SANDBOX_MAIN_* and DEV_* variables, booqy.json (test, dev) on both branches
push to main ──> Deploy ──> dev account sandbox main/sites/<tenantId>/ ──> https://<slug>.test.booqy.se
push to dev  ──> Deploy ──> dev account sandbox dev/sites/<tenantId>/  ──> https://<slug>.test-dev.booqy.se
Domains tab "Add domain example.se" (dev) ──> example-se.test.booqy.se (main) + example-se.test-dev.booqy.se (dev):
                                              both claimed and live at once, host map example-se -> tenantId
```

| Piece | Where |
|---|---|
| Zones | `test.booqy.se`, `test-dev.booqy.se` in the dev account, delegated by NS records in prod's `booqy.se` zone (`prod.tfvars` `platform_subdomain_delegations`) |
| Certificate | one ACM certificate (us-east-1), `*.test.booqy.se` + `*.test-dev.booqy.se` |
| Bucket | `dev-restaurant-sites-test-<account>`: `main/sites/<tenantId>/`, `dev/sites/<tenantId>/`, `_platform/robots.txt` (`Disallow: /`), `_platform/404.html` |
| Serving | ONE standard CloudFront distribution (not multi-tenant: no distribution tenants, which cost money beyond 10 per account), aliases `*.test.booqy.se` and `*.test-dev.booqy.se`, origin the sandbox bucket (OAC); header `X-Robots-Tag: noindex, nofollow` (response headers policy) |
| Host router | CloudFront Function `dev-test-sites-host-router` (viewer request, `test-sites/function/host-router.js`, unit test `node --test test-sites/function/`) with key value store `dev-test-sites-hosts` (label -> tenantId): `<label>.test.booqy.se` -> `/main/sites/<tenantId>/...`, `<label>.test-dev.booqy.se` -> `/dev/sites/<tenantId>/...`; a path without a file extension -> `index.html` (SPA); `/robots.txt` -> `_platform/robots.txt`; unknown host -> 404 page; a missing file -> `_platform/404.html` |
| Host map | written only by `site-repo` (dev): the slug at provision, a mapped domain's label (`example-se`) through the Domains tab (`testHost`), all of the tenant's labels removed on offboarding and purge; a label only for the tenant holding its `DOMAIN#<label>.test.booqy.se` claim |
| DNS | `*.test.booqy.se` and `*.test-dev.booqy.se` alias A/AAAA to the distribution |
| Roles | `/booqy-test-sites/test-site-<slug>-main` and `-dev`, boundary `dev-booqy-test-sites-deploy-boundary`, tags `tenantId`, `stage`, `repo` |
| Domains | buying, connecting and transferring exist only in prod (API 409 `prod_only`, hidden in the dev console, dev IAM without RegisterDomain/TransferDomain); a dev "own domain" is a mapping onto the test zones |

One-time setup (owner):

1. BooqyCustomersDev org settings as for BooqyCustomers (step 2 above):
   Actions allowlist, read-only workflow permissions, base permission None.
   Check that the org's OIDC subject is the default (immutable, ids in it).
2. Test Sites App permissions: Administration, Contents, Actions, Variables
   and Workflows read and write; Metadata read.
3. Its key is the only one in the dev secret `booqy/dev/github-app-sites`,
   `{app_id: "5770798", private_key}` (done by the owner 2026-11-15; step 3
   above). Nothing nested, no other key.
4. The Test Sites App generates from the public
   `BooqyCustomers/site-template`; if GitHub refuses that, see
   Troubleshooting.

Rollout (`test-sites.tf`): `test_sites_zones = true` (zones only) -> the two
NS records in prod (`prod.tfvars`, owner's merge to main, or by hand first)
-> `dig NS test.booqy.se` answers -> `test_sites_enabled = true`.

**Cost:** two hosted zones (about 1 USD/month, approved), one standard
distribution, one CloudFront Function and one key value store, all
request-priced (test traffic only). No distribution tenants, no certificate
per host: a test customer or a mapped domain costs nothing on its own.

Offboarding a test customer removes both roles, every `DEV_*` and
`SANDBOX_MAIN_*` variable and its labels in the host map (so both hosts
answer 404 at once), and archives the repo; delete (or the purge) deletes
the repo in BooqyCustomersDev, both S3 folders and the rows. Dev customers
created before test sites show **legacy** on the Website tab: delete and
re-create them.

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
  `repo:BooqyCustomers@356944191/site-<slug>@<repo id>:ref:refs/heads/main`
  (prod) or `...:ref:refs/heads/dev` (dev), with the owner's login exactly
  as GitHub returns it: GitHub's default subject, which in this
  organisation is the immutable one (ids in it), so a deleted and
  re-created repo with the same name can't use the role. site-repo writes a
  trust only for a repo whose owner is `GITHUB_ORG` (BooqyCustomers) and
  refuses any other. Site repos live in their own organisation, so no
  platform role (`repo:BookingSystemAdvancedOrg@...`) is reachable from a
  site repo, where outside developers have write access. Every platform
  role must still trust only its own repo.
- `<env->site-repo-role` (Terraform, each account): CreateRole and
  PutRolePolicy only on `role/booqy-sites/*` and only with the boundary;
  Get/Tag/UpdateAssumeRolePolicy/ListRolePolicies/DeleteRolePolicy/
  DeleteRole/SimulatePrincipalPolicy on `role/booqy-sites/*`; explicit Deny
  on removing or swapping the boundary and on AttachRolePolicy; tenant table
  Get/Put/UpdateItem; the App secret (prod: Customer Sites, dev: Test Sites
  only). Prod only: `sts:AssumeRole` on
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
  creates (through the normal New customer path, no data copied), adopts or
  restores (offboarded, before its `purgeAt`) the dev tenant with that slug
  (a purged one is replaced; its onboarding creates the dev distribution
  tenant), then has dev `site-repo` (`linkProvision`, synchronous, no
  GitHub call) write the `/booqy-sites/dev-site-<slug>` role for the repo
  prod names, and answers with its ARN and values. Archive removes the dev
  role. Dev has no role or right in prod.
- Onboarding and offboarding state machine roles, platform-tenants role,
  and the `tenant-purge` role (statement `DeleteWebsiteRepo`, only while
  site repos are on): `lambda:InvokeFunction` on the `site-repo` live alias.
- GitHub App: deleting a repo needs Repository permission
  **Administration: Read and write** (already part of step 1).
- Slug addresses: `tenant_subdomains_enabled = true` adds
  `cloudfront:CreateDistributionTenant` / `GetDistributionTenant` (the
  account's multi-tenant distribution only) to the onboarding role, plus
  the `*.<platform domain>` CNAME. Dev since 2026-10-20, prod since
  2026-10-28 (owner-approved). Mounting a domain adds no IAM: prod uses
  platform-tenants' existing domain-attach and restaurant-zone rights; dev
  uses the same link role (site task `domain`, op `status` or `mount`,
  which only runs dev's domain-attach for that slug's dev tenant).

- **Test sites (dev account only, 2026-11-15):** `dev-site-repo-role` gets
  `CreateBoundedTestSiteRoles` (CreateRole, PutRolePolicy on
  `role/booqy-test-sites/*` only with the test boundary),
  `ManageTestSiteRoles` (Get/Tag/UpdateAssumeRolePolicy/ListRolePolicies/
  DeleteRolePolicy/DeleteRole/SimulatePrincipalPolicy there) and
  `KeepTestBoundary` (Deny on removing or swapping it, AttachRolePolicy). The
  runtime roles `test-site-<slug>-main|dev` trust exactly
  `repo:BooqyCustomersDev@356983507/site-<slug>@<repo id>:ref:refs/heads/main`
  (or `dev`) and may write only `<stage>/sites/<tenantId>/` of the sandbox.
  `WriteTestSitesHostMap`: `cloudfront-keyvaluestore:DescribeKeyValueStore`,
  `PutKey` and `DeleteKey` on the one key value store `dev-test-sites-hosts`
  (no other role may write it). No workflow role gets anything for the
  sandbox (no distribution tenants). `dev-tenant-purge` gets
  ListBucket/DeleteObject on `main/sites/*` and `dev/sites/*` of the sandbox
  bucket; `dev-platform-tenants-role` loses `route53domains:RegisterDomain`
  and `TransferDomain` and is denied changes to the two test zones
  (tenant-purge too). Owner guard in site-repo: prod writes roles only for
  BooqyCustomers (login and id 356944191, from GitHub's answer); dev writes a
  real customer's dev role only for BooqyCustomers (login and id) through
  the prod link with the repo id prod supplies, and its test customers'
  roles only for BooqyCustomersDev (login and id 356983507). Dev's GitHub
  client refuses any org but BooqyCustomersDev.

Isolation is checked twice: at setup with the IAM policy simulator
(own folder allowed, another tenant's folder and the bucket root denied;
setup fails otherwise) and on every deploy with a real write that must be
refused.

---

## Troubleshooting

| Symptom | Cause, fix |
|---|---|
| Website tab: "Site repos aren't switched on" | `github_app_sites_secret_name` not set in that environment's tfvars |
| Setup failed: `GitHub POST .../generate: 403` | The App is not installed on `site-template` in BooqyCustomers, or lacks Administration write |
| Setup failed: `refused: ... owner is not BooqyCustomers` | The repo is in another organisation (for example an old one still in BookingSystemAdvancedOrg): transfer it to BooqyCustomers, then Run setup again |
| Setup failed: GitHub 401 or "installation not found" | The secret still holds the old "Booqy Sites" App: step 3, put the new App's key (App ID 5769537) |
| Activity log `site_repo_delete_failed`: "GitHub refused" | The App lacks Administration write (BooqyCustomers settings, GitHub Apps, Booqy Customer Sites, Permissions; then accept the new permission under Installed GitHub Apps). Delete the archived repo by hand meanwhile |
| Setup failed: `refused: ... not a site-* repository name` | Slug not usable as a repo name; never bypass |
| Deploy: `403 Forbidden ... read_package` | The repo can't read the kit: step 4 above |
| Deploy: "No own domain attached and verified" | A repo generated before 2026-10-28 with the old gate: give its `deploy.yml` site-template's "Restaurant is active" step (both branches), then Redeploy main |
| Website tab: slug address "not made yet" | The tenant was onboarded before its environment had slug addresses (prod before 2026-10-28): Domains tab -> **Re-run setup** |
| Website tab: Dev "Unknown" | The prod -> dev link failed (message under it); Refresh |
| Website tab: Dev own domain **Waiting for DNS** | `dev.<domain>` CNAME is missing at the restaurant's DNS provider (bare CNAME domains only) |
| Deploy: "No dev customer for this repo yet" | No `DEV_*` variables: prod hasn't written the dev side (for example a prod customer created before prod had the key isolation code); prod Website tab -> Run setup again |
| Deploy on dev: assume role fails | The dev tenant was offboarded in dev (its role is gone, the `DEV_*` variables stay): prod Website tab -> Run setup again |
| Setup failed: `dev side: ...` | The prod -> dev link failed (dev API, the dev tenant or dev's owner guard); the message names what dev refused. Fix, then Run setup again in prod |
| Dev console Website tab: "managed from the production console" | A real customer's dev side: dev makes no GitHub call for BooqyCustomers. Invite, deploys and Run setup are on the prod console |
| Dev console Website tab: **legacy** | A dev customer from before test sites: delete it and create it again (it becomes a test customer) |
| Test customer setup failed: `GitHub GET /orgs/BooqyCustomersDev/installation: 404` | `booqy/dev/github-app-sites` does not hold the Test Sites key (App ID 5770798), or the App is not installed on BooqyCustomersDev |
| A test host answers "Sidan finns inte" | Its label is not in the host map: the customer is offboarded, the domain mapping was removed, or setup failed before it (Website tab -> Retry) |
| Test customer setup failed: `... is not claimed by ...` | Onboarding did not record the test hosts (`DOMAIN#<slug>.test.booqy.se`): Domains tab -> Re-run setup, then Retry |
| Test customer setup failed: `GitHub POST /repos/BooqyCustomers/site-template/generate: 403/404` | The Test Sites App may not read the template: install it on `BooqyCustomers/site-template` too (Contents read) |
| Deploy: Isolation check failed | Stop. The role can write elsewhere: check the role's boundary and policy in IAM |

## End-to-end test (dev)

Create two test customers A and B in the dev console. For A: the public
repo `BooqyCustomersDev/site-a`, two roles, the variables, `booqy.json` on
both branches, both deploys green, `https://a.test.booqy.se` and
`https://a.test-dev.booqy.se` serve their own builds, both send
`X-Robots-Tag` and `/robots.txt` says `Disallow: /`. A's main role must be
refused on B's folder, A's dev folder and the real dev bucket (the deploy's
isolation step). An unknown `nobody.test.booqy.se` answers 404. Add domain
`example.se` to A: both mapped hosts answer at once; remove it: both 404.
Offboard A (roles, variables, hosts gone, repo archived), restore, then
delete (repo deleted). Delete B. The dev account has no new distribution
tenant afterwards. After the prod merge: one real prod customer (or Run
setup again on `test-release`) to check that prod writes `DEV_*` and dev
made no GitHub call (dev site-repo logs).
