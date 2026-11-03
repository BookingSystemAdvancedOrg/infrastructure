# ADR-A: Meta ads (connect, 2-minute ad wizard, insights)

**Status:** Proposed
**Date:** 2026-11-01
**Deciders:** Owner (product), orchestrator (contracts); Meta App Review and Business Verification (external)
**Run:** built in Run 1 against the Run 0 contract; ADR-G (social posting) reuses the connection in Run 2

## Context

Restaurant owners want local Facebook/Instagram ads without learning Ads
Manager. Booqy already has cookieless visit counting with UTM attribution
(`shared/marketing.py` `channel_of`, `TENANT#<t>#STATS` daily counters per
channel and campaign) and knows what a visit produced (bookings, orders,
revenue, BR-REST-072). It has no Meta integration, no Bedrock, no custom
EventBridge bus and no OAuth flow for tenants. External clients follow
`shared/control_system.py` (port, `Simulated*`, factory from one env var,
simulator refused in prod). Marketing is owner-only in admin.

Hard rules: no Meta Pixel and no Conversions API, ever (BR-NFR-011, BR-GUEST-046);
no guest data leaves Booqy for Meta; spend must be bounded even if Booqy code
misbehaves.

## Decision

1. **Connect with Facebook Login for Business** (configuration id, system
   user access token, long-lived). Top-level redirect to the Meta dialog, no
   Facebook JS SDK, so admin CSP is unchanged. `state` is a server-side
   nonce bound to the owner `sub` (TTL 10 min).
2. **Token per tenant in Secrets Manager** at `booqy/<env>/meta-ads/<tenantId>`
   (created at runtime by the API Lambda, deleted on disconnect and by
   tenant-purge). The Meta app id/secret is one platform secret
   `${prefix}meta-ads/app` (Terraform-created, value set by hand,
   `ignore_changes`; CONTRACTS.md section 11).
3. **Asset picker**: list businesses, ad accounts, Pages and Instagram
   accounts the token can use. A missing asset returns a typed `missing`
   entry with a Meta deep link (create ad account, create Page, link
   Instagram, add payment method) instead of an error.
4. **DSA**: every ad set sets `dsa_beneficiary` and `dsa_payor`, defaulting to
   the tenant `legalName`, editable once in the connection settings.
5. **Wizard** (6 steps, one location): goal (`bookings` | `orders` |
   `catering` | `awareness`) -> creative (a menu item photo from the existing
   menu image bucket; Swedish headline + primary text suggested by Bedrock,
   editable) -> budget (total SEK and 3-30 days) -> radius (1-40 km around
   the location's geocode, age 18+) -> preview (rendered in admin from the
   creative, Feed and Story frames; no Meta iframe) -> create. Create always
   produces a **PAUSED** campaign; a separate "Starta annonsen" activates it.
   Menu items with `alcohol: true` are refused in v1 (alkohollagen).
6. **Spend is bounded three ways**: (a) every ad set uses a **lifetime budget
   with an end date**, so Meta itself stops spending; (b) Booqy caps: total
   budget 100-20 000 SEK per campaign and an owner monthly cap (default
   3 000 SEK, platform ceiling) checked before create and activate;
   (c) a **kill switch**: platform-wide row in the tenant table
   (`PLATFORM#META_ADS` / `SETTINGS`, like `PLATFORM#MAIL`) and per-tenant
   `paused` flag set by operators; when on, create/activate return 409 and
   the jobs Lambda pauses every active campaign. Nightly insights compare
   month-to-date spend with the cap: 80% emails the owner, 100% pauses all
   campaigns. A CloudWatch alarm on the custom metric
   `Booqy/MetaAds PlatformSpendSek` (daily sum) notifies the ops alert topic.
7. **Publish workflow** is a Standard Step Functions state machine
   `<prefix>meta-ads-publish`: CheckGuards -> UploadImage -> CreateCampaign
   (PAUSED) -> CreateAdSet -> CreateCreative -> CreateAd -> MarkPaused, with
   Catch -> MarkFailed. Each task stores the Meta id on the campaign item
   with a condition; a retried task that finds its id skips the call, and a
   task whose call succeeded but whose write was lost looks the object up by
   its name (`booqy-<campaignId>-<step>`) before creating. Activate and pause
   are synchronous API calls (three status updates), guarded by the kill
   switch.
8. **Links carry UTM** `utm_source=facebook|instagram`, `utm_medium=paid_social`,
   `utm_campaign=booqy-<first 10 of campaignId>`, so the existing cookieless
   counters attribute visits, bookings and orders. Nightly insights store
   Meta spend/reach/clicks per campaign and day and compute cost per booking
   and per order from the marketing STATS rows (read-only).
9. **Clients behind ports**: `shared/meta_graph.py` (`MetaGraph`,
   `SimulatedMetaGraph`, env `META_CLIENT` from Terraform `meta_client`) and
   `shared/bedrock.py` (`TextModel`, `SimulatedTextModel`, env `BEDROCK_CLIENT`
   from `bedrock_client`). Both are Run 0 shared scaffolding; ADR-B2 and
   ADR-G use them too. Simulator refused when `ENVIRONMENT=prod`.
10. **Shared with ADR-G** (contract items): the connection routes 1-6
   accept a tenant with `metaAds` **or** `socialPosting` on, and the login
   asks for G's permissions (`pages_manage_posts`,
   `instagram_content_publish`) when `socialPosting` is on; both are on
   the App Review list below.

## Data model

Table `<prefix>meta-ads` (PAY_PER_REQUEST, PITR, deletion protection in prod,
TTL `ttl`). GSI `byConnected` (sparse, `GSI1PK`/`GSI1SK`) lets the nightly job
list connected tenants without a Scan.

| PK | SK | Item |
|---|---|---|
| `TENANT#<t>` | `CONNECTION` | `status` (`connected` \| `needs_reauth` \| `disconnected`), `businessId`, `adAccountId`, `pageId`, `instagramId?`, `currency`, `dsa{beneficiary, payor}`, `monthlyCapSek`, `paused` (operator), `connectedAt`, `connectedBy`, `version`; `GSI1PK=CONNECTED`, `GSI1SK=<t>` while connected |
| `TENANT#<t>` | `OAUTH#<state>` | `sub`, `createdAt`, `ttl` = +10 min |
| `TENANT#<t>` | `CAMPAIGN#<campaignId>` | `locationId`, `goal`, `status` (`publishing` \| `paused` \| `active` \| `completed` \| `failed` \| `rejected`), `creative{menuItemId, imageKey, headline<=40, primaryText<=125, cta}`, `budgetSek`, `startDate`, `endDate`, `radiusKm`, `utmCampaign`, `meta{campaignId, adSetId, creativeId, adId, imageHash}`, `executionArn`, `error?`, `version`, `createdBy`, `createdAt` |
| `TENANT#<t>` | `INSIGHT#<campaignId>#<yyyy-mm-dd>` | `impressions`, `reach`, `clicks`, `spendOre`, `bookings`, `orders`, `revenueOre`, `ttl` = +25 months |
| `TENANT#<t>` | `SPEND#<yyyy-mm>` | `spendOre`, `warnedAt?`, `cappedAt?` |
| `TENANT#<t>` | `COPYUSE#<yyyy-mm>` | `count` (Bedrock suggestions, max 200 per month), `ttl` = +13 months |

`campaignId` is a client-generated ULID. No guest data in this table.

## API routes

Errors `{error, code, field?}`. All JWT routes are **owner only** (marketing
is owner-only today); staff get 403 `owner_only`.

| # | Method | Path | Auth | Role | Request -> response |
|---|---|---|---|---|---|
| 1 | GET | `/tenant/meta-ads/connection` | JWT | owner | -> `{status, assets?, dsa, monthlyCapSek, spendThisMonthSek, killSwitch}` |
| 2 | POST | `/tenant/meta-ads/connection/start` | JWT | owner | `{}` -> `{authorizeUrl}` (stores `OAUTH#<state>`) |
| 3 | POST | `/tenant/meta-ads/connection/callback` | JWT | owner | `{code, state}` -> connection; 400 `invalid_state` |
| 4 | GET | `/tenant/meta-ads/assets` | JWT | owner | -> `{businesses[], adAccounts[], pages[], instagram[], missing[{kind, deepLink}]}` |
| 5 | PUT | `/tenant/meta-ads/connection` | JWT | owner | `{adAccountId, pageId, instagramId?, dsa{beneficiary, payor}, monthlyCapSek, version}` -> connection |
| 6 | DELETE | `/tenant/meta-ads/connection` | JWT | owner | -> 204; pauses campaigns, deletes the secret |
| 7 | POST | `/locations/{locationId}/meta-ads/copy` | JWT | owner | `{menuItemId, goal}` -> `{suggestions[{headline, primaryText}]}`; 429 `quota_exceeded` |
| 8 | POST | `/locations/{locationId}/meta-ads/campaigns` | JWT | owner | `{campaignId, goal, menuItemId, headline, primaryText, budgetSek, days, radiusKm}` -> 202 campaign (`publishing`) |
| 9 | GET | `/locations/{locationId}/meta-ads/campaigns` | JWT | owner | -> `{campaigns[]}` |
| 10 | GET | `/locations/{locationId}/meta-ads/campaigns/{campaignId}` | JWT | owner | -> campaign + `previewUrl?` (Meta shareable preview once created) |
| 11 | POST | `/locations/{locationId}/meta-ads/campaigns/{campaignId}/activate` | JWT | owner | `{version}` -> campaign (`active`) |
| 12 | POST | `/locations/{locationId}/meta-ads/campaigns/{campaignId}/pause` | JWT | owner | `{version}` -> campaign (`paused`) |
| 13 | GET | `/locations/{locationId}/meta-ads/insights?from=&to=` | JWT | owner | -> `{rows[{campaignId, day, spendSek, reach, clicks, bookings, orders, costPerBookingSek, costPerOrderSek}], totals}` |
| 14 | GET | `/platform/meta-ads/settings` | operator | platform_admin | -> `{killSwitch, maxMonthlyCapSek}` |
| 15 | PUT | `/platform/meta-ads/settings` | operator | platform_admin | `{killSwitch, maxMonthlyCapSek}` -> settings (audit row) |
| 16 | PUT | `/platform/tenants/{tenantId}/meta-ads` | operator | platform_admin | `{paused}` -> `{paused}` (audit row) |
| 17 | GET | `/platform/tenants/{tenantId}/meta-ads` | operator | platform_admin | -> `{status, adAccountId?, pageId?, instagramId?, paused, spendThisMonthSek}` (console Integrations tab) |

Errors: 400 `unsupported fields`, `invalid_budget`, `invalid_radius`,
`invalid_days`, `alcohol_not_allowed`, `text_too_long`, `invalid_state`;
403 `feature_not_in_plan`, `owner_only`; 404 foreign or unknown location,
campaign or menu item; 409 `not_connected`, `assets_missing`, `cap_exceeded`,
`kill_switch`, `changed_retry`, `invalid_status`; 502 `meta_unavailable`;
429 `quota_exceeded`.

Idempotency: route 8 Put with `attribute_not_exists` on the client
`campaignId` (same body returns the stored item; the execution name is the
`campaignId`, so a second StartExecution is a no-op); 11/12 conditional on
`version` and `status`, a retry after success returns the campaign; 3 is
single-use on `state`; 6 is idempotent (204 when already disconnected).

## Events

Bus `<prefix>booqy-events`, source `booqy.meta-ads`. Every detail has
`tenantId`, `occurredAt`, `version: 1`.

| detail-type | extra detail |
|---|---|
| `MetaConnection.Connected` | `adAccountId`, `pageId`, `instagramId?` |
| `MetaConnection.Disconnected` | `reason` (`owner` \| `token_revoked` \| `offboarding`) |
| `MetaCampaign.Created` | `campaignId`, `locationId`, `goal`, `budgetSek`, `endDate` (status PAUSED) |
| `MetaCampaign.Activated` | `campaignId`, `locationId` |
| `MetaCampaign.Paused` | `campaignId`, `by` (`owner` \| `cap` \| `kill_switch`) |
| `MetaSpend.CapReached` | `month`, `spendSek`, `capSek` |

ADR-G consumes `MetaConnection.*` to enable or disable posting.

## Terraform modules

- `infrastructure/meta-ads/` (`main.tf`, `variables.tf`, `outputs.tf`):
  table + GSI, Lambdas `meta-ads` (API) and `meta-ads-jobs` (Step Functions
  tasks, nightly insights at 04:00 Europe/Stockholm via Scheduler, kill
  switch sweep), state machine `<prefix>meta-ads-publish` (JSONata ASL in
  `meta-ads/definitions/publish.asl.json`), log groups, Errors alarms, spend
  alarm, roles. Root `meta-ads.tf` passes `var.meta_client` and
  `var.bedrock_client` (declared by Run 0 in `external-clients.tf`); routes
  `network/api-gateway/meta-ads-routes.tf`; operator routes 14-17 on the
  `platform` authorizer, handled by `platform-tenants` in booqy-console,
  which forwards them to `meta-ads` (CONTRACTS.md section 9.3).
- **IAM (new roles; call out):** `secretsmanager:CreateSecret`,
  `PutSecretValue`, `GetSecretValue`, `DeleteSecret` on
  `booqy/<env>/meta-ads/*` (per-tenant, created at runtime);
  `GetSecretValue` on the app secret; `states:StartExecution` on the
  state machine; `bedrock:InvokeModel` on one model/inference profile ARN;
  S3 `GetObject` on the menu-image bucket; `dynamodb:Query` on the marketing
  table (read-only, `TENANT#*#STATS`); `events:PutEvents` on the bus;
  `cloudwatch:PutMetricData` (namespace condition).
- ECR repos are created by Run 0; the module's `wiring` output lists both
  functions for `lambda_releases` and `tenant_aware_role_names`. Purge is
  the `tenant.purge` hook (CONTRACTS.md section 9): `meta-ads` deletes its
  rows and `booqy/<env>/meta-ads/<t>`.

## Entitlement name

`metaAds` (`entitlements.features.metaAds`). Off -> 403 `feature_not_in_plan`.
Not exposed in `/site-config` (no guest-facing part).

## Plan availability (target)

growth (with `marketing`). Run 0 ships `false` in every plan; per-tenant
override in the console.

## UI placement

- Admin, group `restaurangen`, `/marknadsforing?flik=annonser` (new tab
  "Annonser", owner-only like the page): "Koppla Meta" card with the asset
  picker and missing-asset links ("Skapa annonskonto hos Meta"), DSA fields
  ("Annonsör" / "Betalare"), monthly cap; campaign list; "Ny annons" wizard
  (Mål, Bild och text, Budget, Område, Förhandsvisning, Skapa);
  "Starta annonsen" / "Pausa". `?flik=oversikt` gains spend, cost per
  booking and cost per order tiles.
- Console: Settings page "Meta ads" card (kill switch, max monthly cap);
  TenantPage new "Integrations" tab (shared with ADR-D) showing connection
  status and the per-tenant "Pause Meta ads" switch.

## External dependencies

Meta Graph / Marketing API (mocked in Runs 1-2), Bedrock (mocked behind
`TextModel`). **Human actions:** Meta Business Verification of Booqy's
business, App Review for `ads_management`, `ads_read`, `business_management`,
`pages_show_list`, `pages_read_engagement`, `instagram_basic`, and for
ADR-G `pages_manage_posts`, `instagram_content_publish`; a Facebook
Login for Business configuration; Bedrock model access in eu-north-1 (or an
EU inference profile).

## Privacy and GDPR

- Data: business asset ids, the system user token (secret), campaign
  content, aggregated Meta insights. No guest personal data is sent to Meta;
  no custom audiences, no Pixel, no Conversions API, no hashed emails.
- Bedrock gets only the dish name, description, restaurant name and goal.
- Legal basis: contract with the restaurant (Booqy as processor for the
  restaurant's ads tooling). Retention: insights 25 months (`ttl`), campaigns
  while the tenant exists; the token is deleted on disconnect and purge.
- Erase: no guest data, so guest erasure is unaffected.
- Storage registry: no new browser storage (wizard state lives on the
  server as the campaign item; OAuth state is server-side). Admin CSP
  unchanged (redirect, no SDK; previews drawn locally).

## Swedish legal notes (human check)

- DSA art. 26/28 and Meta's EU rules: confirm beneficiary/payor defaults
  (legal name) are right when an agency or owner pays personally.
- Alkohollagen 7 kap.: alcohol ads blocked in v1; confirm before allowing.
- Marknadsföringslagen: ad copy from Bedrock is editable and the owner is
  the advertiser; confirm the owner must approve text before create (we
  require it).
- Prices in ads must include VAT (prisinformationslagen).

## Test plan

Two-tenant fixtures (`tests/tenant_support.py`, `TENANT_A`/`TENANT_B`) in
`mock_aws()`, `SimulatedMetaGraph`, `SimulatedTextModel`. Every route:
happy path, validation error, wrong role, foreign tenant 404, entitlement off
refused, idempotent retry.

| # | Validation | Wrong role | Foreign 404 | Off | Retry |
|---|---|---|---|---|---|
| 1 | n/a (GET) | staff 403 | n/a (own tenant only) | 403 | n/a |
| 2 | unknown field 400 | staff 403 | n/a | 403 | new state each call, old one unusable |
| 3 | bad state 400 | staff 403 | state of B 400 | 403 | second use 400, connection unchanged |
| 4 | not connected 409 | staff 403 | n/a | 403 | n/a |
| 5 | cap above ceiling 400 | staff 403 | adAccount not in token 400 | 403 | stale version 409 |
| 6 | n/a | staff 403 | n/a | 403 | second call 204 |
| 7 | menu item missing 404 | staff 403 | LOC_B, B's menu item | 403 | quota counted once per call |
| 8 | radius 50, days 40, alcohol; location without a stored position 409 `assets_missing` (`field: position`) | staff 403 | LOC_B, B's menu item | 403 | same campaignId -> one item, one execution |
| 9 | any `cursor` query parameter 400; response never carries `cursor` | staff 403 | LOC_B | 403 | n/a |
| 10 | n/a | staff 403 | campaign of B 404 | 403 | n/a |
| 11 | cap exceeded, kill switch 409 | staff 403 | campaign of B 404 | 403 | second activate returns active |
| 12 | stale version 409 | staff 403 | campaign of B 404 | 403 | second pause returns paused |
| 13 | from after to 400 | staff 403 | LOC_B | 403 | n/a |
| 14-16 | bad cap 400 | tenant JWT 401/403 | unknown tenant 404 | n/a | PUT twice same result |

Plus: publish workflow idempotent (rerun each task: no duplicate Meta
objects) and resumable (fail after CreateAdSet, redrive completes); every ad
set has lifetime budget, end date, DSA fields; nightly insights job rerun for
the same day overwrites, never double-counts; cap 80% mail once, 100% pauses
all; kill switch pauses all active campaigns; `META_CLIENT=simulator` refused
with `ENVIRONMENT=prod`; grep test: no `connect.facebook.net`, `fbq(` or
Pixel id anywhere in frontends. **Two-tenant isolation test:** A's owner
lists, reads, activates and reads insights for B's campaign ids and LOC_B:
all 404, B's rows unchanged; the jobs Lambda for A never reads B's secret.

## Alternatives considered

- **Meta Pixel / Conversions API** for attribution: better numbers, but
  tracking cookies and guest data to Meta. Rejected by rule; UTM counts only.
- **Facebook JS SDK login popup**: needs CSP changes and third-party script
  in admin. Rejected for a redirect.
- **Daily budgets with our own stop job**: spend unbounded if our job fails.
  Rejected for lifetime budgets with end dates.
- **Wizard calls Meta synchronously from the API**: five dependent calls,
  partial failures and API Gateway's 30 s limit. Rejected for Step Functions.

## Open questions

1. Does `channel_of` need `paid_social` as its own channel, or are Meta
   visits fine as `facebook`/`instagram`? v1: keep channels, filter by
   `utm_campaign`.
2. Ad account currency other than SEK: refuse in v1?
3. Who receives Meta's ad rejection notices: poll `effective_status` nightly
   (v1) or a webhook later?
4. Bedrock model id and region (eu-north-1 or EU inference profile).
