# Run 0, step 2: explore findings

Read-only exploration of the codebase on 2026-11-01, done on the Run 0
worktrees (`booqy-run0/<repo>`, branch `build/run-0-foundations`, cut from
`dev`). Five Explore agents ran in parallel: application (backend),
infrastructure, admin-front-end, customer-front-end with site-kit, and
booqy-console with booqy-website and the email templates. These are their
conclusions, kept close to what they reported. Paths are relative to the repo
named in each section unless they start with `../`.

## Most important findings for Run 0

- **Entitlements live on the tenant row, not in a resolver.** Plans are
  Terraform `var.plans` rows (`PLAN#<id>`) in the tenant table; the console
  copies a plan's features onto `TENANT#<t>/PROFILE.entitlements` when a
  tenant is created or its plan changes, with per-tenant overrides merged in.
  The override is not stored as its own value: the console works it out by
  diffing the tenant against the plan.
- **The feature flag lists disagree.** `shared/tenant.py` `FEATURES` lacks
  `marketing`; `tenant-site-config` `_FEATURES` lacks `kassa`;
  `tests/tenant_support.py` `ALL_FEATURES` lacks `kassa` and `marketing`; the
  Terraform plan matrix has all six.
- **No custom EventBridge bus and no Bedrock** anywhere. Async work runs on
  DynamoDB Streams; schedules use EventBridge Scheduler; Step Functions only
  for tenant workflows.
- **`application/docs/openapi.yaml` is the natural single contract source**
  (hand-written OpenAPI 3.0.3, 139 paths, checked by `tests/test_openapi.py`),
  but nothing is generated from it today. Every frontend hand-writes types.
- **Simulator pattern to copy for Meta, Google Business Profile, Fortnox and
  Visma:** `shared/control_system.py` (port class, `Simulated*` class, factory
  reading one env var set by a validated Terraform variable, simulator refused
  in prod, credentials in Secrets Manager).
- **Fortnox/Visma already have a slot:** `AccountingTarget` in
  `shared/accounting_export.py`.
- **Two-tenant test fixtures exist** in the backend (`tests/tenant_support.py`
  `seed_tenancy`, `TENANT_A`, `TENANT_B`).
- **Admin routes are not gated**, only the sidebar is; each page guards itself.
- **`@booqy/site-kit` has never been published** from customer-front-end;
  only the separate `booqy/site-kit` repo has a publish workflow.
- **Shared look is copied, not shared:** the console says its code is "the
  same as booqy.se"; admin has its own copies too (oversikt duplicates
  `StatTile`, `countUp`, `liquid` from `shared/motion`).
- **The guest site's `booqy-look.css` hard-codes `--accent: #1a120e`**, so
  the restaurant's own colour (`--tenant-accent`) has no visible effect in
  this app today. This conflicts with the plan's rule that guests see the
  restaurant's brand.
- **Emails are inline-styled Python strings** with inconsistent looks.

---

## 1. application (Python backend)

Repo: `booqy-run0/application`.

### 1.1 Entitlements and features
- **Data shape:** tenant table row `TENANT#<t>/PROFILE` holds `status`,
  `planId`, and `entitlements = {"maxLocations": int, "features": {name: bool}}`.
  Also on the row: `stripe.accountId`, `legalName`, `orgNumber`, `branding`,
  `notifications.sms`, `locationCount`.
- **Resolution:** this repo only reads entitlements. `shared/tenant.py`
  `get_tenant(tenant_id, fresh=False)` is cached per container for
  `TENANT_CACHE_SECONDS` (default 60). `require_feature(tenant_row, feature)`
  reads `entitlements.features`; a missing flag counts as off. Both are used
  inside `for_jwt(...)` and `for_public(...)`.
- **Where plans and overrides come from:** Terraform `var.plans` in
  `../infrastructure/dev.tfvars` seeds `PLAN#<id>/PLAN` rows into the tenant
  table (`storage/dynamodb/tenant`). Booqy Console
  (`../booqy-console/api/src/app/tenants.py`) copies them onto the tenant with
  `_entitlements(plan, overrides)`; per-tenant `overrides.features` and
  `overrides.maxLocations` are merged in at create and in `set_plan`.
- **Refusal when a feature is off:** JWT routes 403
  `{"error":"feature_not_in_plan"}` (`TenantError`); public routes 404 "not
  found". Some handlers check a flag directly instead: `payment-intent:163`
  and `catering-requests:265` (marketing),
  `marketing-public:162` (ordering), `marketing-sync:74`,
  `reservation-reminders:186`.
- **Flag names:** `reservations`, `ordering`, `catering`, `kassa`,
  `marketing`. The lists disagree:

| List | Where | Missing |
|---|---|---|
| `FEATURES` | `shared/tenant.py` | `marketing` |
| `_FEATURES` | `tenant-site-config/app.py` | `kassa` |
| `ALL_FEATURES` | `tests/tenant_support.py` | `kassa`, `marketing` |
| dev plans | `../infrastructure/dev.tfvars` | none (all five) |

- `maxLocations` is enforced with a conditional write in
  `create-location/app.py:~726` (409 `plan_limit_reached`).

### 1.2 Auth and tenancy
- Claims from `event.requestContext.authorizer.jwt.claims`: tenant from
  `tenant_id`, role from `role` (fallback `cognito:groups`), plus `sub`.
  Missing tenant or role: 403 `no_tenant`. Set by the pre-token-generation
  trigger.
- Helpers `tenant.for_jwt(event, location_id=None, feature=None,
  owner_only=False)` and `tenant.for_public(location_id, feature=None)` return
  a `TenantContext` (`tenant_id`, `tenant`, `role`, `sub`, `location`,
  `is_owner`, `location_key`, `stripe_account()`). Errors 401 `unauthorized`,
  403 `owner_only`, 403 `tenant_inactive`. `for_public` also returns 404 when
  `dpa.blocks_public` applies. `shared/auth.py` (`get_claims`, `get_sub`,
  `require_group`) is the older helper.
- Foreign items: `_not_found()` answers 404 "not found", the same as an
  unknown id; the location is loaded by the full key
  `TENANT#<t>/LOCATION#<l>`. Staff are held to their assigned location via
  `staff_location()` (`USER#<sub>/PROFILE`) when the function has
  `USER_TABLE_NAME`. Location-scoped tables are keyed `LOCATION#<l>`.
- Roles: `ROLES = ("owner_user", "staff_user")`; on the user row
  `role: "owner_user" | "staff"`. `super_user` retired; operators use a
  separate pool and authorizer.

### 1.3 Handler pattern
- `functions/<name>/{app.py, requirements.txt, Dockerfile}`; module docstring
  lists TRIGGER, PURPOSE, ENV_VARS, AWS RESOURCE ACCESS.
- Routing: `handler(event, context)` then `method, path = http.route(event)`
  (from `routeKey`), then dispatch on path templates.
- Validation: `http.path_id`, `http.body(event, allowed=...)` (unknown fields
  raise `ValueError("unsupported fields: ...")`), `http.query`, hand-written
  validators raising `ValueError`.
- One error block: `except tenant.TenantError: return exc.response()`;
  `except ValueError: http.error(400, ...)`; `except (BotoCoreError,
  ClientError): 503`.
- Responses: `http.respond` / `http.error` via
  `shared/responses.json_response`, which adds a stable `code` (and `field`)
  to error bodies. Optimistic concurrency: `version` attribute with a
  condition, 409 `changed_retry`.
- Idempotency: no client Idempotency-Key header. Instead Stripe idempotency
  keys (`checkout-<orderId>`, `card-pi-<paymentId>`, `refund-...` via
  `shared/stripe_client.request(..., idempotency_key=)`), a deterministic
  `ClientRequestToken` in `create-location` (~line 763), client-generated ids
  (the till's `paymentId`), and conditional writes.
- Good examples: `functions/catering-settings/app.py`,
  `functions/accounting/app.py`.

### 1.4 DynamoDB conventions
- Names `<env>-<name>` in dev, `<name>` in prod. Code sees env vars only:
  `TENANT_`, `LOCATION_`, `USER_`, `MENU_`, `RESERVATION_`, `SLOT_OCCUPANCY_`,
  `ORDER_`, `CATERING_REQUESTS_`, `CATERING_REQUEST_HISTORY_`,
  `CATERING_MENU_`, `CATERING_DISCOUNT_TIERS_`, `CONSENT_`, `MARKETING_`,
  `FINANCE_`, `INSIGHTS_`, `KASSA_`, `KASSA_JOURNAL_`, `PRINT_`,
  `REQUEST_GUARD_`, `PUBLISHED_LAYOUT_SNAPSHOT_`, `PAYMENT_DELINQUENCY_`, each
  plus `TABLE_NAME`. Access through `shared/dynamo.table(name)` /
  `dynamo.client()`.
- Keys: `PK`/`SK` strings. Tenant rows `TENANT#<t>`; location data
  `LOCATION#<l>/<TYPE>#...`; marketing `TENANT#<t>#SUB`; consent
  `CONSENT#<t>#<subject>`. New writes store `tenantId`.
- GSIs via env vars: `byLocationId` (`LOCATION_ID_INDEX_NAME`), `byTenant` on
  users (`USER_TENANT_INDEX_NAME`), `CONSENT_TENANT_INDEX_NAME`,
  `TENANT_LIST_INDEX_NAME`, kassa-journal `byDay`, print `byDevice`. List by
  key, never Scan with a filter.
- TTL attribute `ttl` (epoch); `expiresAt` is mostly a logical field.

### 1.5 Events
- No custom EventBridge bus, no publisher helper. The only rule is on the
  default bus: SES bounce/complaint/delivery to `marketing-sync`
  (`../infrastructure/marketing/main.tf`).
- Async work on DynamoDB Streams with `ReportBatchItemFailures`:
  `notification`, `marketing-sync`, `print-jobs`, `catering-lifecycle`.
- SQS only as DLQs, drained by `dlq-replay`. Step Functions only in
  infrastructure (tenant onboarding, offboarding, domains).
- Scheduler, recurring: `data-retention`, `tenant-purge`, `finance-rollup`,
  `insights-rollup` (nightly); `reservation-reminders` (15 min);
  `marketing-send` (2 min); `dlq-replay`. One-time, created in code via
  `boto3.client("scheduler").create_schedule`: `catering-lifecycle`,
  `activate-layout-version` then `expire-layout-version`, `no-show-check`.
- Job idempotency: every step idempotent (conditional writes, recomputed
  values overwritten). Long jobs re-invoke themselves async when
  `get_remaining_time_in_millis()` runs low (`data-retention`,
  `tenant-purge`, `finance-rollup`, `insights-rollup`); `marketing-send`
  leases each campaign.

### 1.6 External clients and simulators

| Service | Client | Real vs fake |
|---|---|---|
| Stripe | `shared/stripe_client.py` | `STRIPE_SECRET_ARN`; mode set by the key |
| Signing (BankID / Scrive / simulator) | `shared/bankid.py`, `shared/signing.py`, `shared/signing_scrive.py` | secret `SIGNING_PROVIDER_SECRET_ARN` `{"provider": ...}`; simulator and Scrive testbed refused when `ENVIRONMENT=prod` |
| Kassa control system | `shared/control_system.py` (`ControlSystem`, `SimulatedControlSystem`, `for_location()`), `shared/control_system_fiskaly.py` | `KASSA_CONTROL_SYSTEM` from Terraform `var.kassa_control_system`; `KASSA_CERTIFIED`; fiskaly TEST/LIVE from `FISKALY_SECRET_ID` |
| SES email | `functions/notification`, `shared/marketing_mail.py` | dev outbox `MAIL_OUTBOX_BUCKET_NAME` (Terraform `var.mail_outbox`, refused in prod) |
| SMS | SNS publish in `notification` | no simulator; copied to the outbox in dev; `SMS_ALLOWED_PREFIXES` |
| Turnstile | `shared/turnstile.py` | `TURNSTILE_REQUIRED`, `TURNSTILE_SECRET_ARN` |
| Amazon Location | `shared/geo.py` | none |
| GitHub | `functions/site-repo` | "simulated" dry-run status outside prod |

- No Bedrock or LLM client anywhere.
- Template for new mock clients (Meta, Google Business Profile, Fortnox,
  Visma): follow `control_system.py`.

### 1.7 Accounting (Bokföring)
- `shared/accounting.py` (pure `build_entry`, BAS `DEFAULT_ACCOUNTS`,
  `settings_of` / `validate_settings`), `shared/accounting_export.py` (SIE 4
  in cp437, CSV, `TARGETS`), `functions/accounting/app.py`:
  `GET`/`PUT /locations/{l}/accounting`,
  `GET .../accounting/export?from&to&format=sie|csv|json`.
- Shapes: `Entry(day, series, number, text, lines[Line(account, amount öre,
  text, obj)], warnings, sales, vat, location)`; `Export(company, org_number,
  accounts, entries, ...)`; `Delivery(target, filename, media_type, content,
  references)`. Fortnox and Visma would be new `AccountingTarget` classes
  returning voucher ids in `references`.
- Entries are rebuilt from source records on every export (no stored
  vouchers). Mapping stored on the location row as `accounting`. Docs:
  `docs/ACCOUNTING-EXPORT.md`.

### 1.8 Guest data
- Plain-text `customerName`, `customerEmail`, `customerPhone`, `notes` on
  reservation (`LOCATION#/RESERVATION#<date>#<id>`), order
  (`ORDER#<date>#<id>`) and catering rows. Till payments hold only
  `receiptEmail`.
- Hashing: consent subject `sha256(tenant|channel|identifier)[:32]`;
  marketing subscriber `SUB#<sha256(tenant|email)[:24]>`; manage links
  `manageTokenHash`.
- Consent log: `shared/consent.py`, append-only, `may_send`.
- Retention: `shared/retention.py` (`RETENTION_*` from Terraform
  `var.data_retention`, `*_GUEST_FIELDS`, anonymise helpers), run nightly by
  `functions/data-retention`. Tenant purge: `functions/tenant-purge`.
- GDPR: `functions/guest-privacy` art. 15/20 export (`GET /privacy/guests`)
  and erasure (`POST /privacy/guests/erase`), anonymising bookings, orders and
  catering, deleting subscriber rows, appending an "erasure" withdrawal to the
  consent log. Inventory: `docs/privacy.md`.
- Browser-storage registry is in the frontends, not here.

### 1.9 Domain models
- Menu: `MENU_TABLE_NAME`, `LOCATION#<l>/MENU#<id>`; editable `name`,
  `description`, `price` (whole SEK incl. VAT), `category`, `imageKey`,
  `active`, `alcohol`, `availableFrom`/`availableUntil`
  (`manage-menu/app.py` `_EDITABLE_FIELDS`). No cost field. VAT via
  `shared/orders.vat_rate` (25/12/6).
- Double-booking protection (`shared/reservations.py`): slot-occupancy
  `SLOT#<date>#<s-e>#<table>` holds plus a `LOCK#<date>#<table>` version
  counter in one `transact_write_items`; the loser gets 409. Guest pre-holds:
  `POST /locations/{l}/holds`.
- Kassa (`shared/kassa.py`): kassa table `REGISTER#`, `BILL#`, `RCPT#`,
  `SETUP`, `AUDIT#`; append-only journal `REG#<id>/J#<jseq>` with hash chain
  and `byDay` index. Card payments are taken on the restaurant's own card
  machine and confirmed in Kassa. Gift card redemption needs a new payment
  kind on `BILL#` plus journal and accounting support.
- Staff users: `USER#<sub>/PROFILE` (`tenantId`, `role`, `locationId`,
  `name`, `email`, `phone`, `status`, `createdAt`), GSI `byTenant`, managed by
  `manage-user`.
- Locations: `TENANT#<t>/LOCATION#<l>` (`name`, `address`, `timezone`,
  `businessHours`, `stripeAccountId`, `accounting`, ...); legal
  entity on the tenant row.

### 1.10 `/site-config`
- `functions/tenant-site-config/app.py` (`_site_config`,
  `_public_location`), public, `Cache-Control` max-age 300; lookup by `host`,
  `tenantId`, or `slug` (dev only).
- Fields: `tenant` (tenantId, name, slug, domain, branding, features: 5 flags,
  no kassa); `legal` (legalName, orgNumber, contactEmail, contactPhone,
  address); `locations[]` (guarantee, locationId, name, address, phoneNumber,
  email, timezone, businessHours, bookingDurationHours, maxPartySizeOnline,
  gracePeriodMinutes, specialDays, ordering, catering); `stripe`
  (publishableKey, accountId); `turnstile` (siteKey); `privacy` (notice,
  retention, marketingConsent).

### 1.11 Tests and tooling
- pytest, pytest-xdist, moto (`requirements-dev.txt`). Run
  `cd application && python -m pytest -q -n auto`; CI the same in
  `.github/workflows/reusable_cicd.yml`.
- Flat `tests/test_*.py`, helpers `tests/error_body.py`, `fiskaly_fake.py`,
  fixtures in `tests/fixtures/{fiskaly,scrive,skv_kassaregister_xsd}`. No
  `conftest.py`.
- Two-tenant fixtures: `tests/tenant_support.py` `seed_tenancy(monkeypatch)`
  with `TENANT_A` (LOC_A, LOC_A2, owner and staff) and `TENANT_B` (LOC_B), plus
  `tenant_row(features=...)`, `location_row`, `with_tenant_claims`,
  `claims_for`. Use inside `mock_aws()`.
- No lint or typecheck configured (no ruff, mypy, pyproject, setup.cfg).

### 1.12 Contract and schema generation
- `docs/openapi.yaml`: OpenAPI 3.0.3, hand-written, 139 paths, about 230
  `components.schemas`. `tests/test_openapi.py` validates it
  (`openapi-spec-validator`), checks it lists exactly the implemented
  operations (`EXPECTED_OPERATIONS`), that security matches each route, and
  runs per-handler contract checks. `compose.yaml` serves Swagger UI on 8081.
- Nothing generated from it; the natural single source if `openapi-typescript`
  and `datamodel-codegen` are added. Orchestrator docs treat `openapi.yaml`
  and `test_openapi.py` as one-writer-at-a-time files.

---

## 2. infrastructure (Terraform)

Repo: `booqy-run0/infrastructure` (worktree of `booqy/infrastructure`).

### 2.1 Plans and entitlements
- `variable "plans"` in `variables.tf` (lines 129-157): `map(object({name,
  max_locations, features=map(bool), price_sek}))`, validation: `price_sek`
  whole and >= 0. `dev.tfvars` and `prod.tfvars` set the same matrix:

| id | name | max_locations | reservations | ordering | catering | marketing | kassa | price_sek |
|---|---|---|---|---|---|---|---|---|
| starter | Starter | 1 | T | T | F | F | F | 3950 |
| growth | Growth | 3 | T | T | T | T | F | 8295 |

- Path to Lambdas (not env vars or SSM): `config.tf` passes `var.plans` to
  `module "tenant"` (`storage/dynamodb/tenant`), which writes one
  `aws_dynamodb_table_item.plan` per plan (`PK=PLAN#<id>`, `SK=PLAN`,
  `GSI1PK=PLAN`, `GSI1SK=<id>`, `planId`, `name`, `maxLocations`, `features`,
  `priceSek`, `stripePriceId`, `stripeProductId`). `module "billing_catalog"`
  (`payments/billing`) creates one Stripe product and monthly price per plan
  and feeds the ids back. On assignment the plan is copied to
  `TENANT#<t>|PROFILE.entitlements`; operators override per tenant in the
  console with no deploy. Lambdas read via `TENANT_TABLE_NAME` and the shared
  tenant-context policy.
- Enforcement is in application code. kassa is off in every plan and is
  switched on per tenant in the console.

### 2.2 Module layout and naming
- Legacy per-Lambda (e.g. get-menu): `compute/lambda/<name>/` (`main.tf`:
  log group 30 days, `aws_lambda_function`, env vars; `alias.tf`: `live`
  alias; `package_type="Image"`, `image_uri="<ecr>:latest"`, `publish=true`,
  `arm64`, `ignore_changes=[image_uri]`), `security/iam/<name>/main.tf` (role
  `${fn}-role`, named-Sid item-level statements, logs policy only on its own
  log group), `storage/ecr/<name>/` (scan on push, keep 30 images), wired in
  `config.tf`.
- Newer feature modules (kassa, printing, accounting, marketing,
  sites, site-analytics): root file such as `kassa.tf` with `module "kassa"`
  and the feature's variables, and a directory `kassa/` (`main.tf`,
  `variables.tf`, `outputs.tf`) with tables, role, policies, log group,
  function, `live` alias and an Errors alarm to `alert_topic_arn`.
  `locals { prefix = env=="prod" ? "" : "${env}-"; function="kassa";
  name="${prefix}${function}" }`.
- Naming: `dev-` prefix except prod. Only tag `Environment = var.environment`;
  no `default_tags`.
- Adding a Lambda (in `config.tf`): ECR module; add to `ecr_repository_urls`
  output (CI fails otherwise); add to `module "lambda_releases"` functions map
  (~line 1914); add the role to `local.tenant_aware_role_names` (~2186) for
  `tenant-context-read`; `staff_check_role_names` (~788) if staff act; new
  tenant tables go in `local.tenant_purge_tables` (~2162) and the app's
  tenant-purge function.
- API Gateway (one HTTP API `bsa-api` / `dev-bsa-api`): per feature
  `network/api-gateway/<feature>-routes.tf` and `<feature>-variables.tf`;
  pattern in `kassa-routes.tf` (AWS_PROXY integration payload 2.0, lambda
  permission with alias qualifier, `locals { <x>_routes = [...] }`, `for_each`
  routes with JWT authorizer `cognito`; operator routes use the `platform`
  authorizer plus `platform/admin` scope). Throttling in `main.tf`
  `route_settings`. `ROUTES.md` generated by `python3 generate_routes.py`.
- Least privilege: one role per Lambda, item-level actions, exact secret ARNs
  (`-??????`), optional access via `count`-gated policies.

### 2.3 DynamoDB
- Tables in `storage/dynamodb/<name>/` or the feature module; names
  `env=="prod" ? "<name>" : "${env}-<name>"`; `PAY_PER_REQUEST`, `PK`/`SK`
  strings, SSE (AWS-owned key), PITR on every table, deletion protection in
  prod (except `insights`, `request-guard`, `site-analytics`).
- Append-only Deny resource policies on the kassa journal and
  `catering-request-history`. TTL attribute `ttl`. Streams to Lambdas via
  `aws_lambda_event_source_mapping`.

### 2.4 Eventing
- No custom buses. Rules: SES events to `marketing-sync`; `uptime`. An
  EventBridge connection for Step Functions HTTP tasks to Stripe.
- Scheduler: `aws_scheduler_schedule` in the Lambda's module, default group
  except catering timers (group `${prefix}catering`); target the `live` alias,
  `flexible_time_window OFF`, explicit `retry_policy`; invoke role per
  function.
- Step Functions: `orchestration/tenant-workflows`, five state machines
  (onboarding, domain-attach, domain-detach, domain-provision, offboarding),
  JSONata ASL in `definitions/*.asl.json`.
- SQS only DLQs (`storage/sqs/dead-letter`): 14 days, SSE,
  `DenyInsecureTransport`; replayed by `compute/lambda/dlq-replay` (dev 6
  min, prod 720).
- Releases: `orchestration/lambda-releases` (CodeDeploy), prod 10% canary 5
  min with rollback alarms, dev all-at-once.

### 2.5 Secrets Manager
- Terraform-created: `${prefix}<area>/<name>` (e.g. `stripe/api-key`,
  `catering/link-signing-key`, `catering/signing-provider`,
  `catering/turnstile`, `reservations/link-signing-key`); 30-day recovery in
  prod, 7 elsewhere; hand-set values use `ignore_changes`.
- Hand-made or runtime: `booqy/<env>/...` (`booqy/dev/fiskaly-sign-se`,
  `booqy/<env>/github-app-sites`, per tenant
  `booqy/<env>/fiskaly-unit/<tenantId>`).
- Access: ARN via env var; `GetSecretValue` on exact ARN, `-??????` suffix,
  or a prefix `*` for per-tenant secrets. Never secrets in plain env vars.

### 2.6 Environments and toggles
- `.github/config/project.env` (non-secret CI values as `TF_VAR_*`); Stripe
  key from GitHub secrets.
- `dev.tfvars` / `prod.tfvars`: env, emails, `platform_domain`, `plans`,
  retention, `dlq_replay_interval_minutes`, toggles.
- Kassa toggles (`kassa.tf`): `kassa_control_system` (`simulator` default or
  `fiskaly`, validated; dev `fiskaly`, prod default), `kassa_certified`
  (default false, set nowhere), passed as `KASSA_CONTROL_SYSTEM`,
  `KASSA_CERTIFIED`, `FISKALY_SECRET_ID`, `FISKALY_UNIT_PREFIX`; IAM policies
  `count`-gated on the secret name.
- Other: signing provider chosen by the secret's JSON; `x_enabled = var.y !=
  ""` locals with `count` (`platform_domain_enabled`, `site_repos_enabled`,
  `mail_outbox_enabled`, `rollback_alarms_enabled`); booleans
  `tenant_sites_enabled`, `tenant_subdomains_enabled`, `per_tenant_sites`
  (dev true), `cognito_invites_via_ses`, `data_retention_dry_run`,
  `refresh_token_rotation_enabled`.

### 2.7 CSP, CloudFront and sites
- CSP: admin `network/cloudfront/private/main.tf` `local.admin_csp` (strict
  `'self'`, `connect-src` to the menu-image bucket); console
  `network/cloudfront/platform-admin/main.tf` (adds cognito-idp, API origin,
  upload bucket); restaurant sites `network/cloudfront/public/main.tf` (only
  `frame-ancestors 'none'`, HSTS, nosniff, DENY, CORS for js.stripe.com; real
  CSP is a meta tag in customer-front-end `index.html`).
- Tenant sites: `network/platform-domain/main.tf`
  `aws_cloudfront_multitenant_distribution.tenant_sites` with `tenantId`
  parameter; origins `customer-site`, `menu-image`, `tenant-site`
  (`origin_path="/sites/{{tenantId}}"`); `per_tenant_sites` picks the default
  origin; SPA fallback; wildcard cert; optional WAF.
- Sites bucket `sites/main.tf` `${prefix}restaurant-sites-<account>`,
  private, versioned, readable only by the distribution under `sites/*`.
- Permissions boundary `aws_iam_policy.deploy_boundary`
  (`${prefix}booqy-sites-deploy-boundary`, path `/booqy-sites/`): S3 object
  access only on `sites/${aws:PrincipalTag/tenantId}/*`; the site-repo
  function may create roles under `/booqy-sites/` only with the boundary;
  explicit Deny on removing it. Deploy roles prefixed `${prefix}site-`
  (`DEPLOY_ROLE_PREFIX`); prod reaches dev via `booqy-sites-prod-link`.

### 2.8 Docs
- `docs/MULTI-TENANCY.md`: one deployment per environment; customers, plans
  and domains are data plus workflows, never Terraform; the application is
  the isolation boundary (tenant from JWT `tenant_id`, or `locationId` via
  `byLocationId`, or Stripe `event.account`; foreign location 404; tenant must
  be `active` with the feature in `entitlements`); tenant table layout
  (PROFILE, DOMAIN#, AUDIT#, SLUG#, STRIPE_ACCOUNT#, PLAN#); Stripe Connect
  via `Stripe-Account`; no per-tenant KMS keys, backups or gateway limits.
- `docs/RELEASES.md`: rollout order infrastructure, application, frontends
  and console, same order `dev` then `main`; PR runs fmt, validate, plan (as
  PR comment); merge runs apply, CodeDeploy release, smoke test
  (`ci/smoke-test.sh`); prod deploys on merge to `main` with no approval;
  rollbacks via canary alarms, "Redeploy a commit" or `lambda-release.sh
  --to-version N`; Terraform rollback by `git revert` on `dev` then PR to
  `main`; two SNS alert topics.
- Also relevant: `docs/handoff/BACKEND.md` (tenant-check spec),
  `docs/TENANT-ONBOARDING.md`, `docs/PLATFORM-SETUP.md`,
  `docs/CUSTOMER-SITE-RUNBOOK.md`, `docs/FINANCE.md`,
  `network/api-gateway/ROUTES.md`, `README.md`.

### 2.9 CI
- `.github/workflows/dev.yml` (push or PR to `dev`) and `prod.yml` (`main`)
  call `reusable_cicd.yml`. PR: unit tests (`python3 -m unittest discover` for
  `compute/lambda/pre-token-generation/tests`,
  `compute/lambda/cognito-custom-message/tests`,
  `monitoring/alerts/uptime/tests`), `terraform fmt -check -recursive -diff`,
  `init` (S3 backend `products/bsa/<env>/terraform.tfstate`,
  `use_lockfile=true`), `validate`, `plan` posted to the PR.
- No tflint, checkov, tfsec or pre-commit.
- Local (never apply): `terraform fmt -check -recursive -diff`;
  `terraform init -backend=false && terraform validate`. Terraform
  `>= 1.14.0, < 2.0.0`; providers aws ~> 6.0, lukasaron/stripe ~> 3.0,
  archive, random.

### 2.10 Bedrock and Cognito
- Bedrock: none.
- Tenant pool (`storage/cognito`): groups `owner_user`, `staff_user`,
  immutable `custom:tenant_id`, pre-token trigger adds `tenant_id` and `role`.
  Operator pool (`storage/cognito-platform`): group `platform_admin`, scope
  `platform/admin`, MFA, users from `platform_operator_emails`.

---

## 3. admin-front-end

Repo: `booqy-run0/admin-front-end` (React, Vite, TypeScript; Swedish UI).

### 3.1 Sidebar and routes
- `src/shared/AdminLayout.tsx`: `NavItem = { to, label, tour, end?, feature?,
  ownerOnly?, insights? }`; `NAV_GROUPS` of `{ id, label, items }`:
  `overblick` (`/` Översikt, `/statistik` insights), `passet` ("Under
  passet": `/bokningar`, `/bestallningar` ordering,
  `/kassa` kassa, `/catering` catering), `restaurangen` ("Restaurangen":
  `/meny`, `/layout`, `/marknadsforing` marketing + ownerOnly,
  `/installningar`).
- Filter (~line 222): feature on in `tenant?.entitlements.features`, owner
  check, `canSeeInsights`. Empty groups are not rendered. Collapsed groups in
  `NAV_CLOSED_KEY`. `data-tour` for the guide. "Hjälp" is a separate bottom
  nav.
- Routes: `src/pages.ts` `pages` map of lazy imports (default exports),
  `preloadPages()` at idle; `src/App.tsx` `lazy(pages.x)` routes inside
  `<Route element={<AdminLayout/>}>`; `*` redirects to `/`; `Suspense` with a
  skeleton fallback around `<Outlet key={locationId}>`.
- Routes are not gated; only the sidebar. Pages guard themselves
  (`MarknadsforingPage` "Ingår inte i er plan" / "Bara för ägare";
  `StatistikPage` `canSeeInsights`; Kassa, Catering no check).
- Adding an entitlement-gated slot: feature folder with a default-export page
  (`AdminTopbar` + `admin-main`, guard like `MarknadsforingPage`), `pages`
  entry, `lazy` + `Route` in `App.tsx`, a `NavItem` with `feature`, optional
  `ownerOnly`, `tour: 'nav-<x>'`; optionally a guide step in
  `features/guide/steps.ts` and a mention in `HjalpPage`. No test covers the
  nav; no route-guard component.

### 3.2 Tenant and entitlements
- `src/shared/tenant.ts` `Tenant`: `tenantId`, `name`, `slug`,
  `status:'active'`, `planId`, `entitlements { maxLocations, features:
  Record<string, boolean> }`, `locationCount`, `stripe`, `primaryDomain`,
  `senderName`, `replyToEmail`, `notifications`, `insights?`, `dpa?`, `role:
  'owner_user'|'staff_user'`, `locations`.
- Singleton store via `useSyncExternalStore`; `useTenant()` returns `{ sub,
  status, tenant, error, locationId, refresh }`; also `loadTenant`,
  `replaceTenant`, `selectLocation`, `currentLocation`, `canSeeInsights`,
  `stripeStage`, `getTenant`/`updateTenant`.
- Mock mode `LOCAL_DEMO_TENANT` has `features: {}`, so every feature-gated
  nav item is hidden locally.
- Components read features ad hoc (`OversiktPage:134`,
  `InstallningarPage:449/765/776`, `MarknadsforingPage:43`, `OfferTab:81`,
  `StatistikPage:140`). Known flags: `ordering`, `kassa`,
  `catering`, `marketing`. Tests mock `useTenant` with `vi.mock`.

### 3.3 API client
- `src/shared/api.ts` `apiFetch<T>(path, init)`: Bearer token, JSON,
  `busyStart`/`busyEnd` for non-GET (drives `BusyBar`), retries (429 any
  method; 502/503/504 or dropped connection for GET), throws
  `ApiError(status, message, { code, field, fromServer })` or `NetworkError`,
  `undefined` on 204. `API_BASE_URL` `/api` in prod, `VITE_API_BASE_URL` in
  dev (proxy in `vite.config.ts`).
- Mock mode: `isApiConfigured()` false without `VITE_API_BASE_URL`; each
  feature API branches with inline mocks (`accountingApi`, `privacyApi`,
  `cateringApi`, `kassaApi` in-memory register, `cardApi`, `printApi`,
  `dpaApi`, `guideApi`); separate mock data in `cateringkalkyl/data.ts`,
  `oversikt/sample.ts`, `statistik/insightsSample.ts`. `marketingApi.ts` has
  no mock mode.
- Errors: `src/shared/errors.ts` `errorText`, `errorCode`,
  `focusErrorField`; never show raw server text.

### 3.4 Storage registry
- `src/shared/storageRegistry.ts`: `REFRESH_COOKIE`, `LOCATION_KEY_PREFIX`,
  `LEGACY_LOCATION_KEY`, `GUIDE_KEY_PREFIX`, `LEGACY_SESSION_KEY`,
  `MOCK_SESSION_KEY`, `LOGOUT_PENDING_KEY`, `MOTION_SEEN_KEY`, `THEME_KEY`,
  `SOUND_KEY`, `SOUND_VOLUME_KEY`, `NAV_CLOSED_KEY`, `SAMPLE_DATA_KEY`;
  `STORAGE_REGISTRY: StorageEntry[]` (`name`,
  `kind`, `setBy`, `purpose` in Swedish, `lifetime`, `category`).
- Adding a key: export a constant, add an entry, import the constant in the
  writing file. `features/cookies/CookiesPage.tsx` renders the table.
- `storageRegistry.test.ts`: every category `'nödvändig'`, all fields
  non-empty, any file calling `setItem` must import the registry, no
  `document.cookie =`, no token/session/auth `setItem`.

### 3.5 Feature folders
- `auth` (Cognito/mock login, `RequireAuth`, reset pages); `oversikt`
  (dashboard, `MonthCard`, sample mode; duplicates `StatTile`, `countUp`,
  `liquid` from `shared/motion`); `statistik` (`GET /insights`, charts,
  filters in URL, gated by `canSeeInsights`); `bokningar`; `bestallningar`
  (kitchen/till screen, printer status);
  `kassa` (till, `KassaGuide`, in-memory mock); `catering`;
  `cateringkalkyl`; `meny` (dishes, schedule, images via
  `VITE_MENU_IMAGE_BASE_URL`); `layout-editor` (3D floor plan in CSS);
  `marknadsforing` (owner-only, marketing; tabs by `?flik=`: översikt,
  kampanjer, mallar, erbjudande, mottagare, länkar); `installningar`
  (sections verksamhet, gaster, ekonomi, data, enhet; `BokforingCard` on the
  `bokforing` tab for owners, a role check not a feature check;
  `accountingApi.ts` with chart of accounts and SIE 4/CSV export); `dpa`;
  `guide`; `cookies`.

### 3.6 Design-system code
- Tokens in `src/index.css` (`:root` line 62, dark at 141, reduced-motion
  block): colours (`--bg`, `--surface`, `--surface-glass`, `--ink`, `--muted`,
  `--border`, `--accent*`, `--on-accent`, `--brand`, `--ox*`, `--on-ox*`,
  `--slip`, `--on-slip`, `--fill`), status (`--danger*`, `--success*`,
  `--warning*`, `--green*`, `--purple*`, `--tint-*`, `--trend-good/bad`),
  glass and effects (`--glass`, `--glass-hi`, `--rim`, `--scrim`,
  `--backdrop-veil`, `--shadow*`, `--wall-tint*`, `--liquid-*`), radii
  (`--r-sm`, `--r-md`, `--r-lg`, `--r-panel`, `--r-pill`), type and motion
  (`--font`, `--sans`, `--serif*`, `--display`, `--mono`, `--ease`, `--spring`,
  `--focus`).
- `shared/admin.css` (1,644 lines: shell and generic classes);
  `shared/brand.css` (1,722 lines: brand layer loaded after admin.css);
  `shared/select.css` (`appearance: base-select`).
- `press.ts` (`installPress`, click sound via Web Audio plus ripple,
  `soundOn`, `setSound`, `useSound`, `soundVolume`, `useSoundVolume`,
  `DEFAULT_VOLUME`); `glide.ts` (`installGlide`, `data-glide`,
  `--glide-*`); `theme.ts` (`useTheme`, `setTheme`, `switchTheme`,
  `applyTheme`, `THEME_KEY`); `glassFilter.ts` (`installGlassFilter`, SVG
  `booqy-glass`, `.glass-refract`); all three installed in `main.tsx`.
- `Skeleton.tsx` (`SkelBlock`, `SkelPage`, `SkelHead`, `SkelRows`,
  `SkelTableRows`, `SkelLines`, `SkelChart`, `SkelCard`, `SkelTiles`,
  `SkelBox`, `SkelShell`); `Loading.tsx` (receipt-printing indicator:
  `inline`, `block`, `screen`).
- `motion/`: `busy.ts`, `BusyBar.tsx`, `MotionScope.tsx` (once per login,
  `claimReveal`, `claimNumberReveal`, `sidebarShouldPour`), `Num.tsx`,
  `StatTile.tsx`, `countUp.ts`, `liquid.ts`, `useLiquidFill.ts`,
  `useTrendPop.ts`. Other shared: `AdminTopbar`, `InfoTooltip`, `TrendBadge`,
  `ChartTip`, `DateInput`, `PhoneInput`, `Icon`.

### 3.7 Commands
- Tests: `NODE_OPTIONS=--no-experimental-webstorage npm test` (vitest, jsdom,
  `src/test/setup.ts` stubs `matchMedia` with reduced motion on).
- Lint: `npm run lint` (oxlint, `.oxlintrc.json`). Typecheck: `npx tsc -b`
  (strict, `noUnused*`, `verbatimModuleSyntax`). Build: `npm run build`. Dev
  server port 7070 (strict).

### 3.8 Generated types
- None. Types hand-written per feature `*Api.ts`; the contract is
  `application/docs/openapi.yaml`, only referenced in comments.

---

## 4. customer-front-end and site-kit

Repo: `booqy-run0/customer-front-end`.

### 4.1 Structure, build and publishing
- Root `package.json` (private) `"workspaces": ["packages/*"]`, one package
  `packages/site-kit`; the app depends on `"@booqy/site-kit": "0.1.0"`,
  linked via `package-lock.json`.
- site-kit exports `.`, `./testing`, `./styles.css`, each with conditions
  `"@booqy/source"` (source files) and `types`/`default` (dist).
  `files: [dist, README.md, CHANGELOG.md]`, `sideEffects` for CSS and
  `styles.ts`, `publishConfig.registry: https://npm.pkg.github.com`; react,
  react-dom, react-router-dom as peers.
- Build: `tsc -p tsconfig.json && vite build && tsc -p tsconfig.build.json`;
  lib mode with three entries, `cssFileName: 'site-kit'`, externals,
  `envPrefix: 'SITE_KIT_BUILD_'`.
- The app resolves `@booqy/source` (`vite.config.ts` `resolve.conditions`,
  `tsconfig.app.json` `customConditions`), so dev, tests and build use source
  with no prebuild; the root `build` script still builds site-kit first.
- **No publish job** in this repo; `reusable_cicd.yml` runs `npm ci`, lint,
  test, build, checks `dist/index.html`, deploys to S3/CloudFront. README:
  "Not published yet". `CHANGELOG.md` semver policy: removing or renaming any
  export, CSS variable or class is major.
- Adding `packages/brand`: copy site-kit's `package.json` (`@booqy/brand`,
  three-condition exports, files, publishConfig, peers, scripts),
  `vite.config.ts` (lib mode), `tsconfig.json`, `tsconfig.build.json`; add to
  root dependencies and `npm install`; add build/test scripts to the root. No
  Vite or tsconfig change needed. Publishing would follow
  `booqy/site-kit/.github/workflows/publish.yml` (tag `v*`, check version,
  Node 24, `registry-url`, `npm ci`, lint, test, `npm publish -w
  @booqy/brand`, `NODE_AUTH_TOKEN: secrets.GITHUB_TOKEN`, `packages: write`);
  needs an `.npmrc` mapping the `@booqy` scope (none today).

### 4.2 `/site-config` on the client
- `packages/site-kit/src/shared/site.ts` `SiteConfig`: `tenant { tenantId,
  name, slug, branding, features }`, `legal`, `locations`, `stripe`,
  `turnstile`, optional `privacy`. `SiteBranding`: `logoUrl`, `heroImageUrl`,
  `faviconUrl`, `primaryColor`, `accentColor`, `tagline`, `about`,
  `instagramUrl`, `facebookUrl`. `SiteLocation`: id, name, address, phone,
  email, timezone, `businessHours`, `bookingDurationHours`,
  `maxPartySizeOnline`, `guarantee`, `gracePeriodMinutes`, `specialDays`,
  `ordering`, `catering?`.
- Fetch: `siteQuery(hostname, search, devSlug)` (`host=` on real domains,
  `slug=` on dev hosts), `getSiteConfig` via `apiGet('/site-config?…')`;
  `SiteProvider` handles loading, error, unavailable, no locations, then
  `applyBranding` and `SiteContext`; `useSite()`.
- Gating in `src/App.tsx`: `boka-bord`/`bokningsvillkor` need
  `reservations`, `bestall` needs `ordering`, `catering` needs `catering`;
  guest pages from SMS/email links always exist. Nav links also check the
  location's own flags. `features.marketing` controls `trackPage`. Flows are
  lazy via `sitePages` (`packages/site-kit/src/pages.ts`).

### 4.3 Theming
- site-kit `styles/theme.css`: default "bongrail" look (paper, print),
  `--paper*`, `--surface`, `--ink`, `--muted`, `--font` (Archivo), `--mono`
  (Martian Mono), `--r-*`, spacing; `--accent: var(--tenant-accent, #350001)`,
  `--on-accent: var(--tenant-on-accent, #fff)`; dark mode under both the media
  query and `[data-theme='dark']`.
- App load order (`src/main.tsx`): `@booqy/site-kit/styles.css`, `index.css`,
  `site.css`, `booqy-look.css`.
- **`src/booqy-look.css` hard-codes `--accent: #1a120e`** (around lines
  91-96), adds glass, loads its own fonts (Plus Jakarta Sans, Bricolage
  Grotesque, Newsreader, Martian Mono); its comment says the restaurant's
  colour is not used. So `--tenant-accent` has no visible effect today.
- `applyBranding` (`SiteProvider.tsx`): sets the title; for a valid
  `primaryColor` sets `--tenant-accent`, `--tenant-on-accent`,
  `--tenant-accent-ink`, `--tenant-accent-dark`, `--tenant-on-accent-dark`,
  `--tenant-accent-ink-dark`; swaps favicons. The logo is drawn by the app
  (`CustomerLayout.tsx:114`). `accentColor` and `heroImageUrl` unused there.
- Contrast helpers (exported from `SiteProvider.tsx`): `textOn`,
  `accentPair(hex, 'light'|'dark')` (nudges toward 4.5:1 text, 3:1 against
  the dark surface), `deepenForLight`, `liftForDark`; tests in
  `shared/branding.test.ts`. "BR-NFR-034" appears nowhere in the repo.
- `configureSiteKit` (`packages/site-kit/src/config.ts`): `apiBaseUrl`,
  `devTenantSlug`, `menuImageBaseUrl`, `paymentFonts`.

### 4.4 Storage registry and consent
- `packages/site-kit/src/shared/storageRegistry.ts`: `LOCATION_KEY_PREFIX`,
  `SLUG_KEY`, `CART_KEY_PREFIX`, `TABLE_KEY`, `ORDER_TOKEN_PREFIX`,
  `CATERING_TOKEN_PREFIX`, `OFFER_CARD_KEY`, `THEME_KEY`, `SOUND_KEY`;
  `STORAGE_REGISTRY` entries `{name, kind, setBy, purpose, lifetime,
  category, where?}`; also lists Stripe cookies, Turnstile and cookie-free
  visit statistics.
- Tests: `shared/storageRegistry.test.ts` (all entries strictly necessary and
  described; any file using `setItem` must import the registry; no
  `document.cookie=`); `src/storage.test.ts` (every `script-src` host in
  `index.html` matches a registry vendor).
- No cookie banner on purpose (LEK 9 kap. 28 §). Marketing consent is a
  checkbox in the flows (`shared/MarketingConsent.tsx`).

### 4.5 site-kit features
- `boka` (booking flow, 3D/SVG floor plans, card guarantee, Turnstile);
  `bokning` (`ManageBooking`, token in `#`); `bestall` (order and checkout
  with Stripe, `OrderStatusPage`); `catering` (calculator, quote request,
  `CateringRequestPage` with BankID and payment); `erbjudande` (`OfferCard`
  welcome coupon with email and consent); `juridik` (privacy, cookies from the
  registry, booking terms); `meny` (`Menu`, `CategoryNav`, `DishImage`).

### 4.6 Shared effects
- `shared/sound.ts` (Web Audio click, voices tick/press/cta, `installSound`,
  `setSound`, `soundOn`, `useSound`, `booqy-sound`, Safari wake-up);
  `SoundToggle.tsx`.
- `shared/theme.ts` (`switchTheme` with a 700 ms View Transition circle,
  meta `theme-color`); `public/theme.v2.js` sets `data-theme` before paint;
  `ThemeToggle.tsx`, `ThemeIcons.tsx`.
- `shared/Skeleton.tsx` (`SkelBlock`, `SkelPage`, `SkelLines`, `SkelDishes`,
  `SkelCard`; only `SkelCard` exported).
- `shared/payment/appearance.ts` (`paymentAppearance`, `paymentFonts`,
  `withAlpha`), `stripe.ts`, `PaymentTicket.tsx`.
- Glass only in the app (`booqy-look.css`); sliding pill
  `src/shared/glide.ts` (`installGlide`, `.chip-rail`). Also `Celebrate.tsx`
  (paper confetti) and `Plate.tsx`.

### 4.7 Commands (repo root)
- Lint `npm run lint` (oxlint); site-kit typecheck `npm run typecheck -w
  @booqy/site-kit`; app typecheck via `tsc -b` in the build.
- Tests `NODE_OPTIONS=--no-experimental-webstorage npm test` (site-kit then
  app); separately `npm test -w @booqy/site-kit` and `npx vitest run`.
- Build `npm run build`; package alone `npm run build -w @booqy/site-kit`.
  Dev `npm run dev` on port 7071 (strict).
- The `--no-experimental-webstorage` flag is needed because Node v26's
  built-in webstorage conflicts with jsdom's `localStorage`; it is not in the
  repo's scripts.

### 4.8 Sibling repos (leave untouched)
- `/Users/akoura/projects/it-hjalparna/booqy/site-kit`: standalone repo
  (`BookingSystemAdvancedOrg/site-kit`), published copy
  `@bookingsystemadvancedorg/site-kit` 0.1.0 with a tag-driven `publish.yml`.
- `/Users/akoura/projects/it-hjalparna/booqy/site-template`: standalone repo,
  the restaurant-site template on the published kit, copied to a private
  `site-<slug>` repo per restaurant.

---

## 5. booqy-console

Repo: `booqy-run0/booqy-console` (`web/` React+Vite+TS, English UI; `api/`
Python).

### 5.1 Plans, entitlements and overrides
- Tenant table (`TENANT_TABLE_NAME`; schema in
  `../infrastructure/storage/dynamodb/tenant/main.tf`): plan catalog
  `PK=PLAN#<planId>`, `SK=PLAN` (Terraform-seeded, not editable in the UI);
  tenant `PK=TENANT#<id>`, `SK=PROFILE` with `planId`, `entitlements`,
  `locationCount`, `billing.priceSek` (own price, removed when equal to the
  plan's), `updatedAt`, `updatedBy`; audit `AUDIT#...` with action
  `"plan_changed"` and `{from, to}` details (`write_audit` in `core.py`).
- API (`api/src/app/tenants.py`): `list_plans` (`GET /platform/plans`, GSI1),
  `get_plan`, `_overrides(f)` (body `overrides: {maxLocations 1-100,
  features: {k: bool}}`, errors as `overrides.<k>`), `_entitlements(plan,
  overrides)`, `create_tenant` (`POST /platform/tenants`), `set_plan`
  (`PUT /platform/tenants/{tenantId}/plan`, body `{planId, overrides?, force?,
  priceSek?}`; 409 `below_location_count` unless `force`; then
  `billing.after_plan_change`), `list_tenants`.
- Consequence: stored data does not say which features were overridden; the
  UI diffs against the plan.
- Web: `pages/TenantPage.tsx` `PlanTab` (~line 438, "Plan & limits": plan
  radios, locations allowed, monthly price, feature checkboxes; sends only
  differences as `overrides`; "Apply anyway"; kassa warning); Overview rows;
  "raise limit +1" modal (~line 333); `NewTenantPage.tsx` (lines 107-165,
  318-353) plan picker plus `featureEdits`.

### 5.2 API structure
- One Lambda `platform-tenants`, Python 3.13 container (`api/Dockerfile`), no
  framework. `handler.py` `ROUTES` keyed by `routeKey`; handlers
  `fn(req: Request) -> (status, body)`; non-HTTP `workflowTask`, `mailTask`,
  `financeTask`, `siteTask`.
- Helpers `core.py` (`ApiError`, `respond`, `to_ddb`/`from_ddb`,
  `query_all`, table getters, `write_audit`); `validation.py` (`v.Fields`).
- Operator auth: JWT authorizer on the operator pool (MFA) with
  `platform/admin`; handler also requires `cognito:groups` to contain
  `platform_admin`.
- Tests `api/tests/` (pytest + moto, `conftest.py` creates tables and seeds
  plans); plan tests in `test_api.py`. Run `cd api && pip install -r
  requirements-dev.txt && python -m pytest` (`pythonpath=src`). CI:
  `.github/workflows/{dev,prod,reusable_deploy,redeploy,rollback}.yml`.

### 5.3 Web
- Routes (`main.tsx`): `/` Tenants, `/tenants/new`, `/tenants/:tenantId`,
  `/readers`, `/operators`, `/mail`, `/outbox`, `/finance`, `/website`,
  `/settings`, reset path to `LoginPage`. Pages lazy-loaded.
- `TenantPage` tabs: Overview, Locations, Users, Plan, Payments, Billing,
  Domains, Website, Activity, "Suspend or offboard" (renamed from "Danger
  zone" on dev).
- `src/api.ts` `request<T>` (Amplify bearer token, busy counting, `ApiError`
  with `code` and `fields`); `api.plans()`, `api.setPlan(...)`.
- `src/types.ts`: `Features = Record<string, boolean>`, `Plan`, `Tenant`,
  `TenantSummary`, `TenantDetail`, `AuditEntry`;
  `NewTenantInput.overrides?: {maxLocations?}` is narrower than what
  `NewTenantPage` sends.
- Commands: `npm run dev` (5173), `npm run build`, `npm run typecheck`,
  `npm test` (vitest, jsdom). No lint script or ESLint config, though the
  code carries an `eslint-disable` comment.

### 5.4 Shared-looking UI
- `styles.css` (~1,700 lines, layered): old oxblood/paper tokens, then the
  "glass room" layer from ~line 924 with the six-brown palette (`#1A120E`,
  `#3A2418`, `#6B4A2E`, `#A88462`, `#D5C4AE`, `#4A4A46`), glass and shadow
  tokens (`--glass`, `--glass-hi`, `--rim`, `--lift`, `--lift-sm`), radii
  (`--r-md` 14, `--r-lg` 22, `--r-pill`, `--r-panel` 28), fonts (`--sans`
  Plus Jakarta, `--display` Bricolage, `--serif` Athelas/Newsreader, `--mono`
  Martian Mono); glide pills, skeletons, sound volume, press ripple, theme
  sweep further down.
- `components/motion.tsx` (`prefersReducedMotion`, `useSpring`,
  `easeOutExpo`, `CountUp`, `useTrendPop`, `Delta`, `deltaPct`);
  `press.ts` (click, squeeze, ripple, `booqy-sound`, Safari handling,
  `DEFAULT_VOLUME=40`); `glide.ts`; `glassFilter.ts`;
  `components/Skeleton.tsx` (`SkelBlock`, `SkelPage`, `SkelLines`,
  `SkelRows`, `SkelChart`, `SkelCard`, `SkelKpis`, `SkelTable`,
  `SkelShell`); `busy.ts` + `components/BusyBar.tsx`;
  `components/Ring.tsx` (spring donut), `components/charts.tsx`
  (`BarLineChart`, `LineChart`, `HBarChart`), `ChartTip.tsx`;
  `components/ui.tsx` (`Field`, `Status`, `Notice`, `Printing`,
  `ErrorNotice`, `Card`, `Modal`, `useLoad`, `useAction`, `fmtDate`);
  `components/save.tsx` (`useDirty`, `SaveButton`, `useFlash`, `CheckMark`,
  `RefreshButton`); `theme.ts`, `ThemeToggle`, `SoundToggle`, `SoundVolume`.

---

## 6. booqy-website (booqy.se)

Repo: `booqy-run0/booqy-website`.

### 6.1 Structure and deploy
- `site/`: plain HTML, no build step. Pages `index`, `bordsbokning`,
  `onlinebestallning`, `catering`, `kassasystem`, `hemsida`, `demo`,
  `integritet`, `cookies`, `villkor`, `404` (`.html`), `sitemap.xml`. Each
  page links `/assets/booqy.css`, `/assets/booqy.js`, `/assets/stats.js`
  (`defer`); `demo.html` also `demo.js`. Header and footer copied per page.
- Deploy: `.github/workflows/reusable_deploy.yml` (from `dev.yml`,
  `prod.yml`): `sed` for `{{SITE_DOMAIN}}`, `{{ADMIN_HOST}}`,
  `{{ROBOTS_META}}`, writes `robots.txt`, extensionless copies, `aws s3
  sync`, CloudFront invalidation. Local preview `cd site && python3 -m
  http.server 8080`.
- Docs: `DESIGN.md` (frontmatter tokens: espresso, walnut, graphite, bronze,
  tan, sand), `PRODUCT.md`.
- No shared package; the console copies the website's code.

### 6.2 Visual effects (`assets/booqy.js` ~870 lines, `assets/booqy.css` ~3,300 lines)
- Click sound and ripple (`booqy.js:681+`, `.press-ripple`, `.on-dark`,
  footer "Ljud på/av", `booqy-sound`; CSS `booqy.css:2835`).
- Glass and refraction (`booqy.js:664-680` injects `filter#booqy-glass`;
  "Glass room" tokens `booqy.css:2912+`: `--glass`, `--glass-card`, `--rim`,
  `--lift`, `--wall-rgb`, `--wash`; the source of the console's glass layer).
- Receipts and tickets: rail and tickets (`booqy.css:204`), print-in on
  scroll (`.reveal`/`.is-in`), hero scene, day-picker slips.
- Carousels and tabs: "Så funkar det" (`js:344+`, three-step ring carousel,
  `--p` progress filling the tab pill, dots, play/pause); scroll show
  `[data-show]` (`js:93+`) with a hairline progress; example switcher pill
  (`css:3268`).
- Device mockups: 3D devices (`css:968`), iPhone Pro bodies (`css:1638`),
  MacBook finishes (`css:3196`), real screens from `assets/screens/{dev,prod}`
  (`css:3220`), SMS lock screen (`css:3288`), `[data-tilt]` (`js:507`).
- Bars: sticky header (`--head-h`), `.lnav` chapter bar with a sliding pill
  and a "Demo?" pill (`js:287`, `css:1323-1338`), "Tjänster" menu
  (`js:555`, `css:1938`), "drum fill" bars (`js:484`). No loading or
  progress bar besides the tab-pill progress and the hairline.
- Other: before/after slider (`css:730`), "Ta betalt på plats" animation
  (`css:2416`), `[data-reveal]` (`js:593`).

---

## 7. Email templates (all repos)

No template files: every email is HTML in Python strings with inline styles,
plus a plain-text version.
- `application/shared/messages.py`: guest and staff booking emails
  (`guest_email`, `staff_email`, `guest_sms`), Swedish and English via
  `_TEXT`; 560px div on `#f4f2ee`, white card (`border-radius:10px`), tenant
  brand colour (`_brand_color`, default `#1f2a24`) for the top border and
  CTA; system font stack; detail rows in a presentation table; guest input
  escaped with `html.escape`.
- Same shape: `order_messages.email`, `catering_messages.guest_email` /
  `owner_email`, `card_messages.email`, `kassa_receipt.email`, sent by
  `application/functions/notification/app.py`.
- `application/shared/marketing.py` `render_email`: tenant marketing
  campaigns (600px div, menu images), sent via `marketing_mail.py` (SES raw
  MIME with List-Unsubscribe; dev outbox in S3). Editor:
  `admin-front-end/src/features/marknadsforing/TemplateEditor.tsx`.
- `booqy-console/api/src/app/mail.py` `render_html`: operator newsletters,
  the only table layout with a Booqy look (600px on `#f1eee6`, steel rail,
  `#fbfaf6` paper card, logo, torn edge, accent default `#1a120e`); template
  in the tenant table at `PK=PLATFORM#MAIL`, `SK=TEMPLATE`.
- Others: `infrastructure/compute/lambda/demo-request/src/handler.py`
  (`build_email`); `infrastructure/compute/lambda/cognito-custom-message/src/handler.py`
  (password reset, Swedish for tenants, English for operators); Cognito
  invite text in `infrastructure/storage/cognito/variables.tf` and
  `cognito-platform/main.tf`.
- Inconsistent: transactional emails use a neutral grey look; the console
  newsletter uses the old paper-and-rail look, not the glass six-brown
  palette.
