# Multi-tenancy (SaaS) architecture

One deployment per environment (dev, prod) serves **every** restaurant
company. A new customer, an extra location, a plan change or a custom domain
is data plus a few API calls run by a workflow — never a Terraform change,
a fork or a deploy.

This replaces the earlier silo model (one fork + two AWS accounts per
customer). The trade-off is explicit: tenants no longer have an AWS account
boundary between their data; **the application is the boundary**, enforced
in one shared place (the tenant-context check, below) and covered by
cross-tenant tests.

## Vocabulary

| Term | Meaning |
|---|---|
| Tenant | A customer company (restaurant group) - what you sign and bill. `tenantId` = lowercase ULID (26 chars, `[0-9a-z]`) |
| Location | One restaurant of a tenant. Everything operational (menu, layout, reservations, orders, catering) hangs off a location, as before |
| Plan | A package (`var.plans`): `maxLocations` + feature flags. Copied into the tenant's `entitlements` when assigned, overridable per tenant |
| Operator | You - the people running the platform. Separate Cognito pool, MFA required |
| Owner / staff | A tenant's users (`owner_user` / `staff_user` groups in the tenant pool) |
| Platform domain | The domain you own (`var.platform_domain`); off until set |

## Planes

```
                 OPERATORS                 OWNERS / STAFF              GUESTS
                     │                           │                        │
          platform admin app          restaurant admin app      tenant websites
          (ops.<domain>)              (app.<domain>, shared)    (<slug>.<domain>,
                     │                           │               restaurang.se)
           operator pool JWT            tenant pool JWT          public routes
           + platform/admin scope       (tenant_id claim)        (tenant from location
                     │                           │                or host)
                     └──────────── API Gateway (one) ───────────────┘
                     │                           │
             CONTROL PLANE                APPLICATION PLANE
   platform-tenants, tenant-account,    every existing Lambda, now
   tenant-site-config,                  tenant-aware (shared tenant-
   platform-stripe-webhook              context check)
   + Step Functions workflows
                     │                           │
              tenant table              location (keyed TENANT#), user (+tenantId),
                                        all other tables unchanged
```

## Where each piece lives

| Concern | Resource | Module |
|---|---|---|
| Tenants, domains, plans, Stripe account lookup | `tenant` table | `storage/dynamodb/tenant` |
| Location → tenant | `location` table: PK `TENANT#<t>`, GSI `byLocationId` | `storage/dynamodb/location` |
| User → tenant | `user` table: `tenantId`, GSI `byTenant` | `storage/dynamodb/user` |
| Tenant identity | tenant pool, immutable `custom:tenant_id`, Essentials tier | `storage/cognito` |
| Claims in tokens | `pre-token-generation` (zip, infra-owned) adds `tenant_id`, `role` | `compute/lambda/pre-token-generation` |
| Operator identity | operator pool, MFA, hosted login, `platform/admin` scope | `storage/cognito-platform` |
| Shared read access for the tenant check | `tenant-context-read` managed policy on every app role | `security/iam/tenant-context` |
| Provisioning | Step Functions: onboarding, domain attach/detach, offboarding | `orchestration/tenant-workflows` |
| Platform API | `/platform/*`, `/tenant`, `/site-config` | `network/api-gateway` |
| Stripe | platform key (`stripe/api-key`), Connect webhook endpoints | `security/secrets/platform`, `payments/stripe` |
| Domains, tenant sites, email domain | zone, wildcard cert, multi-tenant distribution, connection group, tenant-sites bucket, SES `mail.<domain>` | `network/platform-domain` (count = platform domain set) |
| Operator app hosting (code: `sbs-admin` repo) | bucket + distribution + deploy role (web + platform-tenants Lambda) | `storage/s3/platform-admin-front-end-asset`, `network/cloudfront/platform-admin`, `security/iam/oidc/platform-admin-front-end-role` |

## Tenant table (control plane)

| PK | SK | Purpose |
|---|---|---|
| `TENANT#<t>` | `PROFILE` | the tenant: status, plan, `entitlements`, `locationCount`, `stripe{}`, `primaryDomain`, sender, branding. `GSI1PK=TENANT`, `GSI1SK=<slug>` |
| `TENANT#<t>` | `DOMAIN#<host>` | a hostname of the tenant: `kind` (platform/custom), `status`, `distributionTenantId`, `cnameTarget` |
| `TENANT#<t>` | `AUDIT#<ts>#<id>` | operator actions (plan changes, suspensions...) |
| `SLUG#<slug>` | `TENANT` | slug uniqueness |
| `DOMAIN#<host>` | `TENANT` | hostname uniqueness + host → tenant (`/site-config`) |
| `STRIPE_ACCOUNT#<acct>` | `TENANT` | Connect webhook → tenant |
| `PLAN#<id>` | `PLAN` | plan catalog (Terraform-seeded). `GSI1PK=PLAN` |

Tenant `status`: `provisioning` → `active` ⇄ `suspended`; `provisioning_failed`
(retryable); `offboarding` → `offboarded`. Only `active` tenants are served.

## The tenant check (every request)

Implemented once in the backend's shared library (spec: `docs/handoff/BACKEND.md`):

1. **Who is the tenant?** Tenant-pool JWT → the `tenant_id` claim (never
   the request). Public route → `{locationId}` → `byLocationId` →
   `tenantId`. Stripe webhook → `event.account` → `STRIPE_ACCOUNT#`.
   Stream/timer → the item's `tenantId`/`locationId`.
2. **Is the resource the tenant's?** Every `{locationId}` must belong to
   the tenant, else 404.
3. **Is the tenant allowed?** `status = active`, feature in `entitlements`.

## Workflows

| Workflow | Started by | Does |
|---|---|---|
| `tenant-onboarding` | `POST /platform/tenants`, `.../onboarding/retry` | first owner (Cognito invite with `custom:tenant_id`) → user profile → Stripe connected account + VAT rates (HTTP tasks) → `<slug>.<domain>` distribution tenant + "coming soon" page → `active` |
| `tenant-domain-attach` | `POST /platform/tenants/{t}/domains` | claim `DOMAIN#<host>` → distribution tenant with a CloudFront-managed certificate → poll until issued (72 h) → `active` |
| `tenant-domain-detach` | `DELETE .../domains/{host}`, offboarding | disable → wait deployed → delete → release the hostname |
| `tenant-offboarding` | `POST /platform/tenants/{t}/offboard` | block → disable + sign out users → detach all domains → `offboarded` |

All four are JSONata ASL with direct SDK integrations - no Lambda code.
Failures email `platform-alerts` with the tenant and cause; the tenant/domain
row records `lastError`. Every step is idempotent: re-running resumes.

## Stripe Connect

Restaurants are **Standard-equivalent connected accounts** (own full Stripe
Dashboard, merchant of record, pay their own Stripe fees) under your
platform account. The platform never holds a restaurant's key:

- every Stripe call = platform key (`STRIPE_SECRET_ARN`) + `Stripe-Account: <tenant's acct_>`
- webhook endpoints are Connect endpoints; `event.account` identifies the tenant
- VAT rates are created per connected account at onboarding (`var.default_tax_rates`) and stored in `PROFILE.stripe.taxRates`
- optional platform fee: `application_fee_amount` on charges/invoices (a product decision, not wired)

## What is gated by `platform_domain`

Unset (default): everything works on `*.cloudfront.net` / `execute-api` URLs,
tenant websites are served by the existing single public distribution (dev
testing with one tenant), emails go from `no_reply_email_address`.

Set: zone + wildcard cert, `app.` and `ops.` hostnames, `<slug>.<domain>` for
every tenant (no per-tenant DNS), customer custom domains (one CNAME each),
SES `mail.<domain>` with DKIM/MAIL FROM/DMARC. See docs/PLATFORM-SETUP.md.

## Isolation guarantees and their limits

| Guarantee | Enforced by |
|---|---|
| A tenant user can never hold platform rights | separate operator pool + issuer check + `platform/admin` scope at API Gateway |
| A user can't move to another tenant | `custom:tenant_id` immutable and not client-writable |
| A token always names exactly one tenant | pre-token trigger refuses tokens without tenant/role |
| Listing locations/users can't cross tenants | tenant in the partition key / GSI key - no filter to forget |
| Owners can't change their plan/status/Stripe account | `tenant-account` IAM: UpdateItem limited to owner-editable attributes |
| Hostnames and Stripe accounts belong to one tenant | conditional uniqueness rows in the same transaction |
| Per-request "this location is yours" | backend tenant-context check - **application code**, so it needs the cross-tenant test suite |

Not provided (would need a silo or bridge model): per-tenant encryption
keys, per-tenant backups/restore (PITR is per table), per-tenant
rate limits at the gateway (HTTP APIs have no usage plans or WAF - use the
CloudFront WAF on tenant sites, `network/platform-domain` `web_acl_arn`).
