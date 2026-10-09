# Backend handoff: multi-tenant SaaS

For the backend (`application` repo) engineer. The infrastructure for
multi-tenancy is in place (see `docs/MULTI-TENANCY.md` for the architecture);
this is the application-side work it needs, in the order to do it. Nothing
is live yet, so there is **no data migration** - change key layouts directly.

Ground rules - every change below follows from these:

1. **The tenant comes from a trusted source, never from the request.**
   Tenant-pool JWT → `tenant_id` claim. Public route → `{locationId}` →
   location row → `tenantId`. Stripe webhook → `event.account`. Never a
   `tenantId` in a path, body, query or header.
2. **Every resource is checked against the tenant** before it is read or
   written. A `{locationId}` that isn't the caller's → **404** (not 403 -
   don't confirm it exists).
3. **List by tenant key, never by filter.** Locations: `Query PK = TENANT#<t>`.
   Users: `Query byTenant`. A Scan + filter is one forgotten line away from
   leaking every customer's data.
4. **Only `active` tenants are served.** And only plan features they have.

---

## 1. What the infrastructure now gives you

### Claims (tenant pool access + ID tokens)

| Claim | Value |
|---|---|
| `tenant_id` | the user's tenant (from immutable `custom:tenant_id`) |
| `role` | `owner_user` or `staff_user` |
| `cognito:groups` | unchanged |

Added by the pre-token-generation trigger (infra-owned). A user with no
tenant or no role can't sign in at all. **`super_user` no longer exists** -
platform operators are in a separate pool and only call `/platform/*`.

### New environment variables

| Variable | On | Meaning |
|---|---|---|
| `TENANT_TABLE_NAME` | every tenant-aware Lambda | tenant table |
| `LOCATION_TABLE_NAME` | every tenant-aware Lambda | location table |
| `LOCATION_ID_INDEX_NAME` | every tenant-aware Lambda | `byLocationId` GSI (locationId → row incl. `tenantId`) |
| `STRIPE_SECRET_ARN` | every Stripe-calling Lambda | **platform** Stripe key, Secrets Manager JSON `{"apiKey": "rk_..."}` |
| `USER_TENANT_INDEX_NAME` | platform-tenants | `byTenant` GSI on the user table |

Removed: `STRIPE_SECRET_KEY` (plaintext key - cancel-reservation,
create-pending-reservation, payment-intent now read `STRIPE_SECRET_ARN`),
`STRIPE_TAX_RATE_IDS` (catering - tax rates are per tenant now).

Changed meaning: `NO_REPLY_EMAIL_ADDRESS` is the platform sender for all
tenants; `CUSTOMER_SITE_URL` is only a fallback (see §4.3);
`ADMIN_DASHBOARD_URL` is the shared admin app.

---

## 2. Data contracts

### 2.1 Tenant table (new) - `TENANT_TABLE_NAME`

`TENANT#<tenantId>` / `PROFILE`:

| Attribute | Type | Notes |
|---|---|---|
| `tenantId` | S | lowercase ULID, 26 chars `[0-9a-z]` (it becomes an S3 prefix and part of CloudFront names - no `_`, no uppercase) |
| `slug` | S | `^[a-z0-9](?:[a-z0-9-]{1,38}[a-z0-9])$`, unique (`SLUG#` row); the `<slug>.<platform domain>` subdomain. Reserved (reject): `app`, `ops`, `www`, `mail`, `api`, `admin`, `bounce`, `status`, `support` - hostnames the platform uses or will use |
| `name`, `legalName`, `orgNumber`, `contactEmail` | S | |
| `status` | S | `provisioning` \| `active` \| `suspended` \| `provisioning_failed` \| `offboarding` \| `offboarded` |
| `planId` | S | |
| `entitlements` | M | `{ maxLocations: N, features: { reservations: BOOL, ordering: BOOL, catering: BOOL } }` |
| `locationCount` | N | maintained by create-location / delete |
| `stripe` | M | `{ accountId: S, chargesEnabled: BOOL, payoutsEnabled: BOOL, detailsSubmitted: BOOL, taxRates: M<key, S txr_> }` (written by onboarding + platform-stripe-webhook) |
| `primaryDomain` | S | base host for every link you send for this tenant (optional) |
| `senderName`, `replyToEmail` | S | email/SMS sender identity (optional) |
| `branding` | M | free-form for the sites (logo URL, colours) |
| `lastError` | S | set when provisioning failed |
| `GSI1PK` / `GSI1SK` | S | `"TENANT"` / `slug` - list tenants via `GSI1` |
| `createdAt`, `createdBy`, `updatedAt`, `updatedBy`, `activatedAt` | S | ISO 8601 |

Other rows (`DOMAIN#`, `SLUG#`, `STRIPE_ACCOUNT#`, `PLAN#`, `AUDIT#`):
see `storage/dynamodb/tenant/main.tf`. Plans: `Query GSI1 GSI1PK = "PLAN"`.

### 2.2 Location table - key layout changed

| | Before | Now |
|---|---|---|
| PK | `PLATFORM` | `TENANT#<tenantId>` |
| SK | `LOCATION#<locationId>` | unchanged |
| new attributes | | `tenantId`, `locationId` (both always set) |
| by id | GetItem | `Query IndexName=LOCATION_ID_INDEX_NAME, locationId = :id` (or GetItem when the tenant is known) |

`locationId`: ULID/UUID (globally unique). Optional `stripeAccountId` on a
location overrides the tenant's Stripe account (a group whose second
restaurant is a separate company/org.nr).

Reference: `compute/lambda/get-location/src/handler.py` (`public-info` is
already updated).

### 2.3 User table

- Every profile gets `tenantId`. `role` ∈ `owner_user`, `staff_user`
  (`super_user` is gone - the Cognito group no longer exists). Staff keep
  `locationId`.
- List a tenant's users: `Query IndexName=byTenant, tenantId = :t`.
  **Remove the "Scan filtered on locationId"** - it reads every tenant.
- The onboarding workflow writes the first owner's profile itself
  (`PK USER#<sub>`, `SK PROFILE`, `cognitoSub`, `tenantId`, `role`,
  `email`, `name`, `status`, `createdBy=platform-onboarding`, `createdAt`).

### 2.4 Everything else

Keys unchanged (they're location-scoped). On **new writes** also store
`tenantId` - it makes a tenant's data exportable/deletable without joins.

S3: put new objects under the tenant:
- menu images: `menu-images/<tenantId>/<locationId>/<file>` (keeps the
  `/menu-images/*` CloudFront path working on every domain)
- catering documents: `<tenantId>/offers/...`, `<tenantId>/signed/...`,
  `<tenantId>/invoices/...` (the 7-year Object Lock still applies)

---

## 3. The tenant-context library (build first)

One module every handler uses. Python reference (adapt if your stack
differs):

```python
# tenant_context.py
import os, time, boto3
from boto3.dynamodb.conditions import Key

_ddb = boto3.resource("dynamodb")
_tenants = _ddb.Table(os.environ["TENANT_TABLE_NAME"])
_locations = _ddb.Table(os.environ["LOCATION_TABLE_NAME"])
_INDEX = os.environ["LOCATION_ID_INDEX_NAME"]
_cache = {}  # per container; TTL keeps suspensions effective within a minute

class NotFound(Exception): ...        # -> 404
class Forbidden(Exception): ...       # -> 403 {"error": code}

def tenant(tenant_id, ttl=60):
    hit = _cache.get(tenant_id)
    if hit and hit[0] > time.time():
        return hit[1]
    item = _tenants.get_item(Key={"PK": f"TENANT#{tenant_id}", "SK": "PROFILE"}).get("Item")
    _cache[tenant_id] = (time.time() + ttl, item)
    return item

def location(location_id):
    items = _locations.query(IndexName=_INDEX,
                             KeyConditionExpression=Key("locationId").eq(location_id),
                             Limit=1).get("Items")
    if not items:
        raise NotFound()
    return items[0]

def require_active(t, feature=None):
    if not t or t.get("status") != "active":
        raise Forbidden("tenant_inactive")
    if feature and not t.get("entitlements", {}).get("features", {}).get(feature):
        raise Forbidden("feature_not_in_plan")

def for_jwt(event, location_id=None, feature=None, owner_only=False):
    """Tenant-pool JWT routes."""
    claims = event["requestContext"]["authorizer"]["jwt"]["claims"]
    tenant_id, role = claims.get("tenant_id"), claims.get("role")
    if not tenant_id or role not in ("owner_user", "staff_user"):
        raise Forbidden("no_tenant")
    if owner_only and role != "owner_user":
        raise Forbidden("owner_only")
    t = tenant(tenant_id)
    require_active(t, feature)
    loc = None
    if location_id:
        loc = location(location_id)
        if loc["tenantId"] != tenant_id:
            raise NotFound()            # never confirm another tenant's id exists
        # staff: additionally check their profile's locationId (as BlockTableFn does)
    return t, loc, role

def for_public(location_id, feature=None):
    """NONE routes - the location decides the tenant."""
    loc = location(location_id)
    t = tenant(loc["tenantId"])
    if not t or t.get("status") != "active":
        raise NotFound()                # suspended tenants look like nothing
    require_active(t, feature)
    return t, loc
```

Also in the library: `stripe_account(t, loc)` → `loc.get("stripeAccountId")
or t["stripe"]["accountId"]`, and `site_base_url(t)` → see §4.3.

Feature keys: reservation routes `reservations`, order routes `ordering`,
catering routes `catering`.

Every log line carries `tenant_id` (and `location_id` when known) -
structured JSON (e.g. Powertools Logger `append_keys`).

---

## 4. Changes to existing Lambdas

### 4.1 Per Lambda

| Lambda | Change |
|---|---|
| **get-location** | `GET /locations` → `Query PK = TENANT#<claims.tenant_id>`. `GET /locations/{id}` via `for_jwt`. `public-info` done (reference in this repo). |
| **create-location** | One `TransactWriteItems`: `Update TENANT#<t>/PROFILE SET locationCount = if_not_exists(locationCount, :0) + :1` with `ConditionExpression #status = :active AND (attribute_not_exists(locationCount) OR locationCount < entitlements.maxLocations)` **+** `Put TENANT#<t>/LOCATION#<new id>` (with `tenantId`, `locationId`) `attribute_not_exists(PK)`. `TransactionCanceledException` on the first item → 409 `{"error":"plan_limit_reached"}`. Owner only. Deleting a location decrements in the same way. `PUT /locations/{id}` → `for_jwt` + update by `TENANT#<t>` key. IAM for the tenant row is in place. |
| **manage-user** | Owner only. Disabling a user (`AdminDisableUser`) also sets their profile `status = "disabled"` (tenant resume relies on it); env `USER_TENANT_INDEX_NAME` for the list. New users: `AdminCreateUser` with `custom:tenant_id = claims.tenant_id` (always the caller's, never from the body), group `owner_user`/`staff_user` only, profile row with `tenantId`. List via `byTenant`. Any read/update/delete of a user: load the profile, `profile.tenantId == claims.tenant_id` else 404. Remove everything `super_user`. |
| **manage-auth** | Unchanged flow. Map Cognito's `PreTokenGeneration failed ...` error to 403 `{"error":"account_not_provisioned"}`. Disabled users (suspended tenant) → 403 `{"error":"account_disabled"}`. |
| **get-menu, get-availability, create-pending-reservation, cancel-reservation, payment-intent** (public) | `for_public(locationId, feature)`. Reservation/order ids in later calls must be checked back to that location. |
| **every JWT route on `/locations/{locationId}/...`** (menu, layout, block-table, orders, catering-offer, catering-settings, catering-discount-tiers, mark-arrived, pre-signed-url...) | `for_jwt(event, location_id, feature)`. Routes keyed by `{reservationId}`/`{orderId}` without a location: load the item, then check its location belongs to the tenant. |
| **pre-signed-url** | Keys under `menu-images/<tenantId>/<locationId>/...` (§2.4); verify the location first. |
| **catering-requests** (public POST) | `for_public(locationId, "catering")`. Turnstile: after `siteverify`, check the returned `hostname` is a domain of THIS tenant (`DOMAIN#<hostname>` → `tenantId` matches - the `<slug>.<platform domain>` subdomain has a `DOMAIN#` row too; outside prod also accept `localhost` and `*.cloudfront.net`). Stops a token minted on one tenant's site being replayed against another tenant. |
| **catering-customer, catering-offer, catering-lifecycle, catering-document, catering-signing-webhook, catering-stripe-webhook** | Tenant from the location of the request. Stripe changes per §5. Tax rates: `tenant.stripe.taxRates[<key>]` (same keys as before, e.g. `food`) instead of `STRIPE_TAX_RATE_IDS`. Signing orders: put `tenantId`, `locationId`, `requestId` in the provider's metadata and verify them in the webhook. Magic links: base URL per §4.3. |
| **notification** | Sender, links and SMS per §4.3. Tenant from the stream item's `tenantId` (new writes) or its location. |
| **stripe-webhook, webhook-payment-intent** | Endpoints are now Connect endpoints - §5.3. |
| **no-show-check, reactivate-menu-item, expire-layout-version, activate-layout-version** | Put `tenantId` into the schedule payloads you create; check the item still belongs to it on fire. |
| **dlq-replay** | No change. |

### 4.2 Errors (same shape everywhere)

| Status | Body | When |
|---|---|---|
| 403 | `{"error":"tenant_inactive"}` | tenant not `active` (JWT routes) |
| 403 | `{"error":"feature_not_in_plan"}` | feature off in entitlements |
| 403 | `{"error":"owner_only"}` | staff calling an owner action |
| 404 | `{"message":"Not found"}` | foreign/unknown id, inactive tenant on public routes |
| 409 | `{"error":"plan_limit_reached"}` | location quota |
| 409 | `{"error":"payments_not_ready"}` | `tenant.stripe.chargesEnabled` false - don't create charges |

The front-ends key their UI off these codes - keep them stable.

### 4.3 Links, email and SMS per tenant

- **Site base URL**: `https://<tenant.primaryDomain>` when set, else
  `CUSTOMER_SITE_URL` (dev / before the platform domain). The workflows
  keep `primaryDomain` right: onboarding sets `<slug>.<platform domain>`,
  attaching a custom domain with "make primary" replaces it, detaching
  the primary falls back to the subdomain. Use it for magic links and
  Checkout success/cancel URLs.
- **Email** (SES): `From: "<senderName or name>" <NO_REPLY_EMAIL_ADDRESS>`,
  `Reply-To: <replyToEmail or contactEmail>`. Never send From a tenant's
  own domain - it isn't verified in SES.
- **SMS**: sender ID from `senderName` (max 11 chars, `[A-Za-z0-9 ]`),
  else the platform default.

---

## 5. Stripe Connect

### 5.1 Every call on the restaurant's account

```python
import json, os, boto3, stripe
stripe.api_key = json.loads(boto3.client("secretsmanager")
    .get_secret_value(SecretId=os.environ["STRIPE_SECRET_ARN"])["SecretString"])["apiKey"]
stripe.api_version = os.environ.get("STRIPE_API_VERSION")

acct = tenant_context.stripe_account(t, loc)
if not t["stripe"].get("chargesEnabled"):
    raise Conflict("payments_not_ready")
session = stripe.checkout.Session.create(..., stripe_account=acct,
                                         idempotency_key=f"checkout-{request_id}-{attempt}")
```

Node: `stripe.checkout.sessions.create(params, { stripeAccount: acct, idempotencyKey })`.

Applies to **every** Stripe object: Checkout Sessions, PaymentIntents,
SetupIntents, Customers, Invoices/InvoiceItems, Credit Notes, Refunds, Tax
Rates. Objects live on the connected account, so retrieve/update them with
the same `stripe_account`. Store `acct` next to every Stripe id you persist.

**Contract with the websites:** every response that returns a Stripe
`client_secret` (payment-intent, create-pending-reservation's SetupIntent)
also returns `"stripeAccountId": acct`. The site initialises Stripe.js with
that account - a client secret only resolves on the account it was created
on, and a location may override the tenant's account.

### 5.2 Card-on-file (reservations)

The SetupIntent is created on the connected account; the website mounts
Stripe Elements with `Stripe(pk, { stripeAccount: acct })` (`pk` from
`/site-config`, `acct` from the response carrying the client secret). Later off-session charges
(cancellation/no-show fees) use the same `stripe_account`.

### 5.3 Webhooks

- `stripe-webhook`, `webhook-payment-intent`, `catering-stripe-webhook`
  now receive **Connect** events: tenant = `STRIPE_ACCOUNT#<event.account>`
  row in the tenant table. Unknown account → 200 + log (don't make Stripe retry).
- Check `event.livemode`: dev processes test events only, prod live only
  (a live Connect endpoint also receives connected accounts' test events).
- Cross-check `metadata.locationId` of the object against the tenant.
- Signing secrets unchanged in mechanism (`*_WEBHOOK_SECRET_ARN`).

### 5.4 Platform fee (optional, product decision)

`application_fee_amount` on PaymentIntents/Checkout (`payment_intent_data`)
and invoices. Not wired - decide pricing first.

### 5.5 Testing

`stripe listen --forward-connect-to <url>` and
`stripe trigger checkout.session.completed --stripe-account acct_...`.
Create a test connected account through dev onboarding (§6.1).

---

## 6. New Lambdas (container images, like the others)

ECR repos, roles, functions and routes exist; the placeholder image answers
501 until you deploy. IAM is scoped to exactly what is described here - if
you need more, ask for an infra change rather than working around it.

### 6.1 platform-tenants - `/platform/*` (operator token, `platform/admin` scope)

> **Already implemented - not yours to build.** The code lives in the
> `sbs-admin` repo (`api/`, Python, with tests) and is deployed by that
> repo's pipeline; the backend deploy role is explicitly denied on this
> function. The table below is the contract it implements, kept here
> because the other Lambdas depend on the rows it writes. Additional
> routes it has: `GET .../users`, `GET|POST .../locations`,
> `PATCH|DELETE .../locations/{locationId}`, `POST .../stripe/sync`.

API Gateway already rejects anything but an operator-pool token with the
scope; additionally check `cognito:groups` contains `platform_admin` and
record `claims.email` as `requestedBy`/`updatedBy` + an `AUDIT#` row for
every change.

| Route | Behaviour |
|---|---|
| `GET /platform/plans` | `Query GSI1 GSI1PK="PLAN"` |
| `GET /platform/tenants` | `Query GSI1 GSI1PK="TENANT"`; return `tenantId, name, slug, status, planId, locationCount, entitlements.maxLocations, stripe.chargesEnabled, primaryDomain` |
| `POST /platform/tenants` | Body `{name, slug, ownerEmail, ownerName, planId, legalName?, orgNumber?, contactEmail?}`. Validate (slug pattern, email, plan exists). New `tenantId` (lowercase ULID). One `TransactWriteItems`: `Put SLUG#<slug>/TENANT {tenantId}` `attribute_not_exists(PK)` + `Put TENANT#<t>/PROFILE {..., status:"provisioning", entitlements: from plan, locationCount:0, GSI1PK:"TENANT", GSI1SK:slug}`. Then `StartExecution(ONBOARDING_STATE_MACHINE_ARN, name="onboard-<tenantId>-1", input={tenantId, slug, name, ownerEmail, ownerName})`, store `onboardingExecutionArn`. → `202 {tenantId, status:"provisioning"}`. Slug taken → 409. |
| `GET /platform/tenants/{tenantId}` | PROFILE + `DOMAIN#` rows (`Query PK, begins_with(SK,"DOMAIN#")`) + locations (`Query` location table `PK=TENANT#<t>`) + user count (`byTenant`) + `DescribeExecution(onboardingExecutionArn)` status |
| `PATCH /platform/tenants/{tenantId}` | `name, legalName, orgNumber, contactEmail, senderName, replyToEmail, branding` |
| `PUT /platform/tenants/{tenantId}/plan` | `{planId, overrides?: {maxLocations?, features?}}` → `entitlements` = plan + overrides. `maxLocations < locationCount` → 409 unless `force` (existing locations stay, no new ones). Audit row. **This is the "upgrade to 2 locations" action.** |
| `POST /platform/tenants/{tenantId}/suspend` | `status=suspended`; for every user (`byTenant`): `AdminDisableUser` + `AdminUserGlobalSignOut`. Don't touch the users' profile `status`. |
| `POST /platform/tenants/{tenantId}/resume` | `status=active`; `AdminEnableUser` only for users whose profile `status = "active"` - users an owner disabled (manage-user sets their profile `status = "disabled"` when it calls `AdminDisableUser`) stay disabled |
| `POST /platform/tenants/{tenantId}/offboard` | Body `{confirmSlug}` must equal the slug → `StartExecution(OFFBOARDING_STATE_MACHINE_ARN, input={tenantId, requestedBy})` |
| `POST /platform/tenants/{tenantId}/onboarding/retry` | Re-runs onboarding (`name="onboard-<t>-<n+1>"`, same input as the first run); every step is idempotent. `provisioning_failed` → set `provisioning` first. `active` → leave the status as is: the run skips the owner invitation and only fills what is missing (VAT rates added to `default_tax_rates` later, the `<slug>` subdomain once the platform domain exists); a failure alerts but never takes the tenant offline. Other statuses → 409. |
| `POST /platform/tenants/{tenantId}/owners` | Invite another owner: `AdminCreateUser` (`custom:tenant_id`, `email_verified`), `AdminAddUserToGroup owner_user`, profile row with `tenantId` |
| `POST /platform/tenants/{tenantId}/domains` | Body `{domain, makePrimary?}`. 409 when `PLATFORM_DOMAIN` is empty (`platform_domain_not_configured`). Validate hostname; reject `*.PLATFORM_DOMAIN` and wildcards; pre-check `DOMAIN#<host>`: owned by another tenant → 409 `domain_in_use`; owned by this tenant and its row is `validation_timeout`/`failed` → allowed (the workflow resumes - "add again" after fixing DNS); this tenant and any other status → 409 `domain_exists`. `StartExecution(DOMAIN_ATTACH_STATE_MACHINE_ARN, input={tenantId, domain, makePrimary, requestedBy})`. → `202 {domain, status:"pending_dns", dns: [{type:"CNAME", name: domain, value: TENANT_DOMAIN_CNAME_TARGET}]}` |
| `DELETE /platform/tenants/{tenantId}/domains/{domain}` | Refuse `kind=platform` (409). `StartExecution(DOMAIN_DETACH_STATE_MACHINE_ARN, input={tenantId, domain})` → 202 |
| `POST /platform/tenants/{tenantId}/stripe/account-link` | **Accounts v2** account link: `POST /v2/core/account_links` (JSON) with `{"account": t.stripe.accountId, "use_case": {"type": "account_onboarding", "account_onboarding": {"configurations": ["merchant"], "refresh_url": f"{PLATFORM_ADMIN_APP_URL}/tenants/{t}?stripe=refresh", "return_url": f"{PLATFORM_ADMIN_APP_URL}/tenants/{t}?stripe=return"}}}` → `{url, expiresAt}` (links expire in minutes - never store them). Accounts are v2 accounts (created by onboarding); don't use `/v1/account_links` or `/v1/accounts` create. Reading them with `GET /v1/accounts/{id}` is fine - Stripe answers in the v1 shape, and v1 `account.updated` webhooks still fire. |

Workflow statuses the dashboard shows come from the rows the workflows
write (`PROFILE.status/lastError`, `DOMAIN#.status/lastError`) - no need
to parse executions beyond the onboarding summary.

### 6.2 tenant-account - `/tenant` (tenant pool token)

| Route | Behaviour |
|---|---|
| `GET /tenant` | Caller's tenant (`claims.tenant_id`): `name, slug, status, planId, entitlements, locationCount, stripe{chargesEnabled, detailsSubmitted, payoutsEnabled}, primaryDomain, domains[]{domain, status, kind, primary (= domain == primaryDomain)}, senderName, replyToEmail, branding`. Don't return operator-only fields (`lastError`, `onboardingExecutionArn`,
`AUDIT#` rows). |
| `PATCH /tenant` | Owner only. Only `senderName`, `replyToEmail`, `branding` (+ `updatedAt/updatedBy`) - **IAM rejects anything else**, and `ReturnValues` must be `NONE`/`UPDATED_*`. |
| `POST /tenant/stripe/account-link` | Owner only. Account link as above with `refresh_url=f"{ADMIN_APP_URL}/settings/payments?stripe=refresh"`, `return_url=f"{ADMIN_APP_URL}/settings/payments?stripe=return"`. |

### 6.3 tenant-site-config - `GET /site-config` (public)

Query `host=<hostname>` (lowercase, strip port) **or**, outside prod,
`slug=<slug>` (sites on `*.cloudfront.net` can't be mapped by host).

1. `DOMAIN#<host>` → `tenantId` (or `SLUG#<slug>`); the tenant's `DOMAIN#`
   row must be `status=active`.
2. PROFILE `status=active`, else 404.
3. Locations: `Query location PK=TENANT#<t>` → public fields only.
4. Response (cache `Cache-Control: public, max-age=300`):

```json
{
  "tenant": { "tenantId": "...", "name": "...", "slug": "...", "branding": {}, "features": {"reservations": true, "ordering": true, "catering": false} },
  "locations": [ { "locationId": "...", "name": "...", "address": "...", "phone": "...", "openingHours": {} } ],
  "stripe": { "publishableKey": "<STRIPE_PUBLISHABLE_KEY>", "accountId": "acct_..." },
  "turnstile": { "siteKey": "<TURNSTILE_SITE_KEY>" }
}
```

Never return owner contacts, plan internals, `lastError`, tax rate ids or
Stripe readiness details.

### 6.4 platform-stripe-webhook - Function URL, paths `/connect` and `/billing`

Verify `Stripe-Signature` with the secret for the path
(`CONNECT_WEBHOOK_SECRET_ARN` / `BILLING_WEBHOOK_SECRET_ARN`); wrong path → 404.

- `/connect` `account.updated` → tenant via `STRIPE_ACCOUNT#<event.account>`
  → **retrieve the account** (`stripe.Account.retrieve(event.account)`;
  Stripe doesn't guarantee event order, so never write the payload's
  snapshot) → `SET stripe.chargesEnabled = charges_enabled,
  stripe.payoutsEnabled = payouts_enabled, stripe.detailsSubmitted =
  details_submitted, stripe.requirementsDue = requirements.currently_due,
  stripe.updatedAt`.
- `/connect` `account.application.deauthorized` (the restaurant disconnected
  the platform in its Stripe dashboard) → `SET stripe.chargesEnabled=false,
  stripe.disconnected=true`, log at ERROR with `tenant_id`. Payments for
  that tenant stop (`payments_not_ready`) and the operator dashboard shows
  it; reconnecting = a new onboarding account link.
- `/billing` `customer.subscription.created|updated|deleted` (only once
  you sell plans via Stripe Billing): tenant from `subscription.metadata.tenantId`
  (set it when creating the subscription); plan from the price's
  `lookup_key` = `planId`; per-location pricing → `quantity` = `maxLocations`.
  Write `planId` + `entitlements` exactly like `PUT /plan`. `deleted` →
  don't delete anything; flag `billing.status="canceled"` for the operator.
- `/billing` `invoice.payment_failed` → `billing.pastDue=true` (no
  automatic suspension - operator decides).

Return 200 for events you ignore.

---

## 7. Tests that must exist before go-live

1. **Cross-tenant suite**: two tenants A and B, each with a location, user,
   reservation, order, catering request. For every route: A's token / A's
   ids against B's resources → 404 (or 403 for `/platform/*`). Run in CI.
2. Suspended tenant: JWT routes 403 `tenant_inactive`, public routes 404,
   login 403 `account_disabled`.
3. Plan limit: two concurrent create-location calls at `maxLocations-1` →
   exactly one succeeds.
4. Stripe: every created object is on the tenant's account (`stripe_account`
   set) - assert in unit tests by mocking the client.
5. Webhooks: unknown `event.account` → 200 + no write; livemode mismatch ignored.

## 8. Order of work

1. Tenant-context library + location/user key changes + `get-location`,
   `create-location`, `manage-user` (gets you a working tenant #1 end to end).
2. Apply `for_jwt` / `for_public` everywhere (§4.1) + the cross-tenant suite.
3. Stripe Connect (§5) - all payment flows, then the three webhooks.
4. `tenant-account`, `tenant-site-config`,
   `platform-stripe-webhook` (§6).
5. Notification sender/links (§4.3).
