# Customer sites: runbook

Every restaurant has its own private website repo `site-<slug>` in
BookingSystemAdvancedOrg, designed in Figma by Booqy and coded with Claude
on top of `@bookingsystemadvancedorg/site-kit`. Guests only ever see the
restaurant's own domain. Plan and decisions:
`application/docs/orchestrator/CUSTOMER-SITES-PLAN.md`.

```
dev console "New customer" ──> site-repo (dev) ──> repo site-<slug> from site-template
                                                    booqy.json (dev), DEV_* variables,
                                                    role /booqy-sites/dev-site-<slug>
push to dev  ──> Deploy ──> dev account  sites/<tenantId>/ ──> <slug>.dev.booqy.se (noindex)
prod console "New customer", same slug ──> site-repo (prod) finds the repo:
                                                    booqy.json (prod), PROD_* variables,
                                                    role /booqy-sites/site-<slug>
merge dev -> main ──> Deploy ──> gate: own domain verified? ──> prod sites/<tenantId>/ ──> restaurant.se
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

Restaurant data is never copied between environments: the restaurant enters
its menu and everything else in the admin app, in dev (test data) and in
prod separately.

---

## One-time setup (owner)

### 1. Register the GitHub App "Booqy Sites"

GitHub -> BookingSystemAdvancedOrg -> Settings -> Developer settings ->
GitHub Apps -> **New GitHub App**:

- Name: `Booqy Sites`. Homepage URL: `https://booqy.se`.
- Webhook: **untick Active** (none is used).
- Repository permissions:
  - Administration: **Read and write** (create from the template, default
    branch, archive and unarchive, invite collaborators)
  - Contents: **Read and write** (`booqy.json`)
  - Actions: **Read and write** (OIDC subject per repo, start and read deploys)
  - Variables: **Read and write** (the `DEV_*` / `PROD_*` repo variables)
  - Workflows: **Read and write** (the generated repo contains `.github/workflows`)
  - Metadata: Read (required)
- Organization permissions: none. Account permissions: none.
- Where can this GitHub App be installed: **Only on this account**.
- Create. Note the **App ID** at the top of the page.
- **Generate a private key** (bottom of the page). A `.pem` file downloads.
  Never paste it anywhere else, never commit it, never send it in chat.

### 2. Install it on the site repos only

App page -> **Install App** -> BookingSystemAdvancedOrg -> **Only select
repositories** -> `site-kit` and `site-template` (plus any existing
`site-*`). Never "All repositories", never a platform repo. Repos the App
creates later are added to the installation by GitHub automatically.

### 3. Store the key in both accounts

Secrets Manager, region eu-north-1, in the **dev** account and again in the
**prod** account, the same way as the fiskaly key: Store a new secret ->
Other type of secret -> Plaintext, name `booqy/dev/github-app-sites` (prod:
`booqy/prod/github-app-sites`), value:

```json
{"app_id": "<App ID>", "private_key": "-----BEGIN RSA PRIVATE KEY-----\n...\n-----END RSA PRIVATE KEY-----\n"}
```

(the PEM with each line break written as `\n`). Or from a terminal signed
in to that account, without the key ever appearing on screen:

```bash
jq -n --arg id "<App ID>" --rawfile key ~/Downloads/booqy-sites.*.private-key.pem '{app_id:$id, private_key:$key}' > /tmp/gh-app.json && aws secretsmanager create-secret --region eu-north-1 --name booqy/dev/github-app-sites --secret-string file:///tmp/gh-app.json && rm /tmp/gh-app.json
```

Then delete the downloaded `.pem`. Only the `site-repo` role can read the
secret. Rotate yearly: generate a new key on the App page, update both
secrets, delete the old key on the App page.

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

`dev.tfvars`: uncomment `github_app_sites_secret_name`, push. New dev
customers now get their repo. For customers created before: their Website
tab says "No site repo yet" with **Set up**.

When every active dev restaurant with a domain has a deployed site,
uncomment `per_tenant_sites = true` in `dev.tfvars` so their domains serve
their own site instead of the shared customer-front-end build. Same two
lines in `prod.tfvars` when production moves over.

---

## Per customer

1. Booqy designs the site in Figma (duplicated from "Booqy site - start").
2. Dev console -> **New customer** (the slug becomes the repo name:
   `site-<slug>`).
3. Onboarding creates the restaurant, then the repo from `site-template`
   (branches `dev` and `main`, default `dev`), its deploy role, repo
   variables and `booqy.json`, and deploys. About 2 minutes.
4. Website tab: status **Ready**, Dev **Live**; **Open dev preview**
   (`https://<slug>.dev.booqy.se`).
5. The restaurant owner enters menu, hours and the rest in the admin app
   (dev, test data).
6. **Give access** to the developer's GitHub username (write on this repo only).
7. The developer: **Get started locally** (clone, `npm install`, `npm run dev`).
8. Code the design on `dev` with Claude and the kit's components.
9. Every push to `dev` deploys to the dev preview; the restaurant reviews it there.
10. Restaurant approves the preview.
11. Prod console -> **New customer** with **the same slug**.
12. Prod onboarding finds `site-<slug>`, adds the prod part of `booqy.json`
    and the `PROD_*` variables, creates the prod role. Nothing deploys yet.
13. The restaurant enters its real menu and settings in the prod admin app.
14. Prod console -> Domains: buy or connect the restaurant's domain; wait
    for **Live** (certificate issued).
15. Prod console -> Website -> **Run setup again** (writes the domain into
    `booqy.json`, so the dev preview's canonical link names it).
16. PR `dev` -> `main` in the site repo, review, merge.
17. Deploy (main): the go-live gate asks the prod API for the verified
    domain; with it, the site goes live on the restaurant's domain.
18. Check the site on its domain (booking, order, catering).

A customer created directly in prod (no dev repo) gets its repo the same
way; its first deploy waits for step 16.

### Deploys and rollback

- `dev` -> dev account, `main` -> prod account. The prod deploy refuses
  while the restaurant has no attached, verified own domain (GitHub Free
  has no branch protection on private repos, so the rule is in the deploy).
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

Offboarding a customer (Danger zone) also runs `site-repo archive` for that
environment: its deploy role and `DEV_*`/`PROD_*` variables are removed; the
repo is archived (read-only, never deleted) once no environment uses it.
The Website tab has the same as **Archive**. **Set up** (or onboarding in
the other environment) unarchives it. The site's files stay in
`sites/<tenantId>/`; the domain is detached by offboarding, so nothing
serves them.

---

## IAM

Owner-approved 2026-10-27. Nothing here touches the platform's own OIDC
roles (`dev-infra-oidc-role`, the front-end and back-end deploy roles).

- `/booqy-sites/<env->booqy-sites-deploy-boundary` (Terraform, `sites/`):
  permissions boundary; S3 Put/Get/Delete on `sites/${aws:PrincipalTag/tenantId}/*`
  and ListBucket with that prefix, in the sites bucket only.
- `/booqy-sites/<env->site-<slug>` (created by `site-repo`, one per
  customer per account): that boundary, tag `tenantId`, inline policy
  `deploy-own-site` with the same rights for its literal tenant. Trust: the
  account's existing GitHub OIDC provider, audience `sts.amazonaws.com`,
  subject exactly
  `repository_owner_id:<org id>:repository_id:<repo id>:ref:refs/heads/dev`
  (dev) or `.../main` (prod). Site repos use that custom OIDC subject (set
  by `site-repo`), so their tokens never match a platform role's
  `repo:...` pattern; repo ids also survive renames.
- `<env->site-repo-role` (Terraform): CreateRole and PutRolePolicy only on
  `role/booqy-sites/*` and only with the boundary attached; Get/Tag/
  UpdateAssumeRolePolicy/ListRolePolicies/DeleteRolePolicy/DeleteRole/
  SimulatePrincipalPolicy on `role/booqy-sites/*`; explicit Deny on removing
  or swapping the boundary and on AttachRolePolicy; tenant table
  Get/Put/UpdateItem; the App secret.
- Onboarding and offboarding state machine roles, platform-tenants role:
  `lambda:InvokeFunction` on the `site-repo` live alias.

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
| Deploy: "No own domain attached and verified" | Prod gate: attach the domain in the prod console first |
| Deploy: "No dev customer for this repo yet" | No `DEV_*` variables: Website tab -> Run setup again |
| Deploy: Isolation check failed | Stop. The role can write elsewhere: check the role's boundary and policy in IAM |

## End-to-end test (dev)

Use slugs starting with `test-` (repos `site-test-<slug>`): create two
customers in the dev console, check both deploy, both Isolation checks
pass, then Archive both on the Website tab (or offboard them).
