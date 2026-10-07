# Front-end handoff: multi-tenant SaaS

For the front-end engineer. One deployment now serves every restaurant
(tenant); `docs/MULTI-TENANCY.md` has the architecture and
`docs/handoff/BACKEND.md` the API contracts these screens call. Three apps
are affected:

| App | Repo | Who uses it | URL |
|---|---|---|---|
| Restaurant admin (existing) | `admin-front-end` | owners + staff of **every** restaurant | `admin_app_url` output - `https://app.<platform domain>` once set |
| Platform admin (**new**, built - `sbs-admin` repo) | `sbs-admin` | you (operators) - create and manage tenants | `platform_admin_app_url` output - `https://ops.<platform domain>` once set |
| Restaurant websites | `site-<slug>` per restaurant (from a template) | the restaurants' guests | `https://<slug>.<platform domain>` + the restaurant's own domain |

Ground rules:

- **Never send a tenant id to the restaurant API.** The backend takes it
  from the token (admin app) or from the location (websites). Only the
  operator app addresses tenants by id (`/platform/tenants/{tenantId}`).
- API calls use `Authorization: Bearer`, never cookies (CORS is `*`
  because restaurant domains are added at runtime).
- Error codes are a contract (BACKEND.md §4.2) - branch on `error`, not on
  message text:

| Status + `error` | Show |
|---|---|
| 403 `tenant_inactive` | full-screen "account suspended - contact support"; stop polling |
| 403 `feature_not_in_plan` | "not included in your plan" + upgrade hint |
| 403 `owner_only` | hide the action (shouldn't be reachable) |
| 409 `plan_limit_reached` | "your plan includes N locations - contact us to upgrade" |
| 409 `payments_not_ready` | admin: link to Settings → Payments; website: "online payment is temporarily unavailable" |
| 404 | not found - also what a foreign id or a suspended restaurant looks like |

---

## 1. Restaurant admin app (`admin-front-end`)

One app for all restaurants - nothing tenant-specific in the URL or the
build. Hosting and deploy are unchanged.

### 1.1 Sign-in and claims

- Login flow unchanged (`/auth/*`).
- The ID and access tokens now carry `tenant_id` and `role`
  (`owner_user` | `staff_user`). Read the role from `role` rather than
  deriving it from `cognito:groups`.
- **`super_user` is gone.** Remove platform-wide views (all restaurants,
  restaurant switcher, creating restaurants) - that moves to the operator app.
- Login errors: `account_not_provisioned` → "this account isn't linked to
  a restaurant - contact support"; `account_disabled` → "this account is
  suspended".
- Invited owners/staff get an email with a temporary password linking to
  the app root - the existing first-login "choose a password" flow applies.

### 1.2 Tenant context (new)

- After login: `GET /tenant` → keep in app state: `name, status, planId,
  entitlements {maxLocations, features}, locationCount, stripe
  {chargesEnabled, detailsSubmitted, payoutsEnabled}, primaryDomain,
  domains[], senderName, replyToEmail, branding`. Refetch after creating a
  location and after returning from Stripe.
- **Feature gating:** hide Reservations / Ordering / Catering when
  `entitlements.features.reservations|ordering|catering` is false. Still
  handle 403 `feature_not_in_plan` (plan can change while the app is open).
- **Locations:** `GET /locations` now returns only this restaurant's
  locations. Show a location picker when there is more than one; every
  location-scoped call uses the selected `locationId`.
- **Add location** (owner only): disable with the upgrade message when
  `locationCount >= entitlements.maxLocations`; handle 409
  `plan_limit_reached` the same way (two tabs can race).

### 1.3 Roles

| | owner_user | staff_user |
|---|---|---|
| Daily operations of their location(s) | yes | own location only |
| Users, payments, settings, add location | yes | hidden |
| Invite users | `owner_user` / `staff_user` only | - |

The backend enforces all of this; the UI only hides what can't be used.

### 1.4 Settings → Payments (new) - route **`/settings/payments`**

The path is a contract: Stripe sends the owner back to
`/settings/payments?stripe=return` (done/left) or `?stripe=refresh` (link
expired).

| `GET /tenant` → `stripe` | Show |
|---|---|
| no account / `detailsSubmitted=false` | "Connect Stripe to take online payments" + **Set up payments** |
| `detailsSubmitted=true`, `chargesEnabled=false` | "Stripe needs more information" + **Continue setup** |
| `chargesEnabled=true` | "Online payments active" |
| `payoutsEnabled=false` (with charges enabled) | warning: "payouts paused - check your Stripe dashboard" |

- Button → `POST /tenant/stripe/account-link` → `window.location.assign(url)`
  right away (links expire within minutes - never store or email them).
- `?stripe=return` → refetch `GET /tenant`; the status arrives by webhook,
  so poll every 3 s for up to 30 s before showing "still processing".
- `?stripe=refresh` → request a new link and redirect again.
- "Open Stripe dashboard" → `https://dashboard.stripe.com` (owners sign in
  to their own Stripe account; refunds, payouts and disputes live there).
- Banner on the start page while `chargesEnabled` is false: online
  payments are off.

### 1.5 Settings → Profile (new)

- `PATCH /tenant` (owner only) with any of:
  - `senderName` - From name on emails, SMS sender (max 11 chars,
    letters/digits/space - validate in the form);
  - `replyToEmail` - where guests' replies go;
  - `branding` - JSON object the websites read. Agree the keys with the
    website template, start with `{ logoUrl, primaryColor, accentColor }`.
- Domains: read-only list from `GET /tenant` `.domains[]` (domain, status,
  primary). "To use your own domain, contact us" - the operator adds it.

---

## 2. Platform admin app (repo `sbs-admin`) - already built

The operator console. Separate Cognito pool with MFA; calls only `/platform/*`.
**Implemented** in the `sbs-admin` repo (`web/` = this app, `api/` = the
platform-tenants Lambda behind it) - see its README. The rest of this
section documents what it does, for maintenance.

### 2.1 Hosting and deploy

- The repo name must be exactly `sbs-admin` (the deploy role trusts that
  name; `PLATFORM_ADMIN_FRONTEND_REPO` in `.github/config/project.env`).
- Its pipeline (`.github/workflows/deploy.yml` in sbs-admin) uses role
  `platform-admin-front-end-deploy-role` (prod) /
  `dev-platform-admin-front-end-deploy-role` (dev), which can deploy exactly:
  - the web app: bucket `platform_admin_front_end_bucket_name`, invalidate
    `platform_admin_cloudfront_distribution_id`;
  - the API: push to the `platform-tenants` ECR repo, update the
    `platform-tenants` function.
- Until the first deploy, infra CI publishes a placeholder page there.
- SPA routing works (403/404 → `/index.html`).

### 2.2 Sign-in: Cognito hosted login, authorization code + PKCE

`tofu output platform_operator_login` gives `user_pool_id`, `client_id`,
`hosted_login_url`, `scope`. Public client - no secret.

```ts
// e.g. oidc-client-ts / react-oidc-context
const oidc = {
  authority: `https://cognito-idp.eu-north-1.amazonaws.com/${USER_POOL_ID}`,
  client_id: CLIENT_ID,
  redirect_uri: `${window.location.origin}/auth/callback`,
  response_type: "code",                       // PKCE is automatic
  scope: "openid email profile platform/admin",
};
// Logout: Cognito has no OIDC end_session endpoint - redirect yourself:
// `${HOSTED_LOGIN_URL}/logout?client_id=${CLIENT_ID}&logout_uri=${encodeURIComponent(window.location.origin + "/")}`
```

- **Send the access token**, not the ID token: API Gateway checks the
  `platform/admin` scope, which only the access token carries.
- Allowed origins (callback `/auth/callback`, logout `/`): the app's
  CloudFront domain, `https://ops.<platform domain>` once set, and
  `http://localhost:5173` outside prod - run the dev server on port 5173.
- MFA (authenticator app) is enforced; the hosted page handles enrolment
  on first sign-in. Sessions last 8 h (refresh token), then sign in again.
- Operators are created by Terraform (`platform_operator_emails`) and get
  an email with a temporary password.

### 2.3 Screens

API details in BACKEND.md §6.1.

**Tenants** - `GET /platform/tenants`: name, slug, status badge, plan,
locations used/allowed, payments ready (`stripe.chargesEnabled`), primary
domain. Filter by status.

**New tenant** - form → `POST /platform/tenants`:

| Field | Rule |
|---|---|
| Restaurant name | required |
| Slug | suggested from the name (lowercase, `a-z0-9-`, 3-40 chars, no leading/trailing `-`, not a reserved name like `app`/`ops`/`www`/`mail`); shown as `<slug>.<platform domain>`; 409 = taken |
| Owner email, owner name | required - gets the invitation |
| Plan | `GET /platform/plans` |
| Legal name, org. number, contact email | optional |

Returns 202 with `status: "provisioning"` → go to the tenant page and poll.

**Tenant detail** - `GET /platform/tenants/{tenantId}`; poll every 5 s
while `status = provisioning` or any domain is `pending_*`/`removing`:

- *Status*: `provisioning` (spinner) → `active`. `provisioning_failed` →
  show `lastError` + **Retry onboarding** (`POST .../onboarding/retry`).
  The same call on an `active` tenant is **Re-run provisioning** (secondary
  button): fills in what was added to the platform later (VAT rates,
  subdomain).
- *Profile*: edit → `PATCH`.
- *Plan*: plan picker + optional overrides (max locations, features) →
  `PUT .../plan`. 409 when lowering below the current location count →
  confirm and resend with `force: true`. **This is the "upgrade to 2
  locations" button** - takes effect immediately, no deploy.
- *Payments*: Stripe status + **Create onboarding link** (`POST
  .../stripe/account-link`) → show the URL with a copy button and a
  "expires in a few minutes" note - for when you complete Stripe setup on
  a call with the restaurant. Normally the owner does it from their own
  admin app (§1.4).
- *Domains*: list (`domain`, `kind` platform/custom, `status`, primary,
  `lastError`). **Add domain** → `POST .../domains {domain, makePrimary}` →
  show the DNS record from the response (`CNAME <domain> → <value>`).
  **Remove** → `DELETE .../domains/{domain}` (not for `kind=platform`).
- *Owners*: list + **Invite owner** (`POST .../owners {email, name}`).
- *Danger zone*: **Suspend** / **Resume** (confirm dialog), **Offboard**
  (type the slug to confirm → `POST .../offboard {confirmSlug}`).

Domain status texts:

| status | Meaning / action |
|---|---|
| `pending_dns` | waiting for the restaurant to add the CNAME |
| `pending_validation` | DNS found, certificate being issued (minutes) |
| `active` | live on HTTPS |
| `validation_timeout` | the CNAME never appeared (~3 days) - fix DNS, then **Add domain** again (resumes) |
| `failed` | show `lastError`; **Add domain** again retries |
| `removing` | being detached |

Apex domains (`restaurang.se` without `www`) can't be a CNAME at most DNS
providers: recommend `www.restaurang.se` + a redirect from the apex at the
registrar, or a DNS provider with ALIAS/ANAME/CNAME flattening.

---

## 3. Restaurant websites

### 3.1 Model

- One site per restaurant, in its own repo named **`site-<slug>`** (the
  deploy role trusts `site-*` in the org). Create a GitHub *template
  repository* (e.g. `site-template`) from today's `customer-front-end`;
  a new restaurant = "Use this template" + set `TENANT_ID`.
- Every site is served by one shared CloudFront distribution from
  `s3://<tenant-sites bucket>/<tenantId>/`. Onboarding puts a "coming soon"
  page there; the first deploy replaces it.
- Same API as today; what changes is how the site finds its restaurant,
  Stripe, and deploys.

### 3.2 Startup: `GET /site-config`

```ts
const host = window.location.hostname;
const isDevHost = host === "localhost" || host.endsWith(".cloudfront.net");
const q = isDevHost ? `slug=${import.meta.env.VITE_TENANT_SLUG}` : `host=${host}`;
const res = await fetch(`${API}/site-config?${q}`);
if (res.status === 404) return renderUnavailable();   // unknown or suspended
const cfg = await res.json();
// cfg.tenant { tenantId, name, slug, branding, features }
// cfg.locations [{ locationId, name, address, phone, openingHours }]
// cfg.stripe { publishableKey, accountId }   cfg.turnstile { siteKey }
```

- `slug=` works outside prod only.
- Show reservations / ordering / catering only when `cfg.tenant.features`
  says so.
- More than one location → location picker; pass `locationId` to the
  public endpoints exactly as today.
- Menu images keep the same `/menu-images/...` URLs on every domain.

### 3.3 Stripe.js on the restaurant's account

Payments are created on the restaurant's own Stripe account, so Stripe.js
must be told which account:

```ts
const { clientSecret, stripeAccountId } = await createPaymentIntent(...);
const stripe = await loadStripe(cfg.stripe.publishableKey, { stripeAccount: stripeAccountId });
```

Use the `stripeAccountId` returned with each client secret (a location may
use a different account than `cfg.stripe.accountId`). Without it confirm
fails with "No such payment_intent/setup_intent". Catering's Stripe-hosted
pages are unchanged.

### 3.4 Turnstile

Site key from `cfg.turnstile.siteKey`. Turnstile only runs on hostnames
registered on the widget in Cloudflare - the platform domain and every
custom domain must be on that list (operator step, see
`docs/TENANT-ONBOARDING.md`). Use Cloudflare's test site keys locally.

### 3.5 Deploy (GitHub Actions)

```yaml
permissions:
  id-token: write
  contents: read
env:
  TENANT_ID: 01j9...            # from the operator app - never derived from input
  BUCKET: tenant-sites-343695380960      # tenant_sites_bucket_name output
jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: arn:aws:iam::343695380960:role/tenant-sites-deploy-role
          aws-region: eu-north-1
      - run: npm ci && npm run build
      - name: Publish (assets first, HTML last)
        run: |
          aws s3 sync dist/ "s3://$BUCKET/$TENANT_ID/" --exclude "*.html" \
            --cache-control "public,max-age=31536000,immutable"
          aws s3 sync dist/ "s3://$BUCKET/$TENANT_ID/" --exclude "*" --include "*.html" \
            --cache-control "no-cache"
```

- Hashed assets cached forever, HTML revalidated on every request → **no
  CloudFront invalidation needed**. (If ever required, the role can call
  `create-invalidation-for-distribution-tenant` with the distribution
  tenant ids shown on the tenant page of the operator app.)
- No `--delete` on assets: a guest with the old HTML open still needs the
  old files. Bucket versioning + lifecycle handle cleanup.
- The role can technically write any tenant's prefix (IAM can't tie a
  repo to a tenant) - `TENANT_ID` is hard-coded per repo and pipeline
  changes go through review. `_placeholder/` is blocked.
- Dev: same with the dev account (`877653167825`, role
  `dev-tenant-sites-deploy-role`, bucket `dev-tenant-sites-877653167825`).
  These exist once `platform_domain` is set for that environment; until
  then test against the existing public distribution with `?slug=`.

---

## 4. Contracts that must match the backend

| What | Value |
|---|---|
| Stripe return - admin app | `/settings/payments?stripe=return` and `?stripe=refresh` |
| Stripe return - operator app | `/tenants/{tenantId}?stripe=return` and `?stripe=refresh` |
| Operator OAuth callback / logout | `/auth/callback` / `/` |
| Invitation email link | admin app root |
| Site bootstrap | `GET /site-config?host=` (prod), `?slug=` (dev) |
| Stripe account for Stripe.js | `stripeAccountId` returned with every client secret |

## 5. Order of work

1. Admin app: claims, `GET /tenant`, feature gating, location picker,
   remove super_user (works as soon as backend step 1 lands).
2. Operator app: sign-in, tenant list, create, detail.
3. Admin app: Payments and Profile settings.
4. Website template: `/site-config`, Stripe account, deploy pipeline;
   convert today's customer site into the template.
