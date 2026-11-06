# Booqy build ownership (Runs 0-3)

Who may create or edit which files. Paths are relative to the repo named in
the heading. `**` = everything below, including tests in that folder.

**Default rule: a file not listed under a feature is read-only for that
feature.** Reading, importing and referencing shared code (Python imports,
TS imports, Terraform `module.<x>.<output>` references) is always allowed;
editing is not. A feature that needs a change outside its list stops and
reports it to the orchestrator (RULES.md, Scope).

Contract and design references: `docs/build/CONTRACTS.md` (section numbers
below point there), `docs/adr/ADR-<letter>-*.md`, `docs/design/DESIGN.md`.

## 1. Per feature

Naming: `<id>` = kebab feature id, `<snake>` = Python package name
(CONTRACTS.md section 0). Every feature owns the same kinds of paths; the
tables list the exact ones.

### Common pattern (every feature)

| Repo | Paths the feature owns |
|---|---|
| application | `functions/<id>/**` and its extra Lambdas' `functions/<id>-*/**`; `shared/features/<snake>/**`; `docs/openapi/<id>.yaml`; `docs/features/<id>.md`; `tests/test_<snake>*.py` |
| infrastructure | `<id>/**` (module, incl. its `README.md`, `definitions/`); `<id>.tf` (root file); `network/api-gateway/<id>-routes.tf` |
| admin-front-end | `src/features/<id>/**` |
| booqy-console | `api/src/app/features/<snake>.py`, `api/tests/test_feature_<snake>.py`, `web/src/features/<id>/**` (only features listed in 8.3 of CONTRACTS.md) |
| customer-front-end | only the site-kit folders listed for the feature |
| booqy-website | nothing |

### A. Meta ads (`meta-ads`)

| Repo | Owns |
|---|---|
| application | `functions/meta-ads/**`, `functions/meta-ads-jobs/**`, `shared/features/meta_ads/**`, `shared/meta_graph_real.py`, `shared/bedrock_real.py`, `docs/openapi/meta-ads.yaml`, `docs/features/meta-ads.md`, `tests/test_meta_ads*.py` |
| infrastructure | `meta-ads/**` (incl. `meta-ads/definitions/publish.asl.json`), `meta-ads.tf`, `network/api-gateway/meta-ads-routes.tf` |
| admin-front-end | `src/features/meta-ads/**` (`AnnonserTab.tsx`, `AdsOverviewTiles.tsx`, wizard, API client) |
| booqy-console | `api/src/app/features/meta_ads.py`, `api/tests/test_feature_meta_ads.py`, `web/src/features/meta-ads/**` (`MetaAdsTenantSection.tsx`, `MetaAdsSettingsCard.tsx`) |
| customer-front-end | nothing |

A must also expose module outputs `table_name`, `table_arn`,
`tenant_secret_prefix` for G (read-only use).

### B. Site builder (`site-builder`)

| Repo | Owns |
|---|---|
| application | `functions/site-builder/**`, `shared/features/site_builder/**`, `shared/site_schema/**` (incl. `v1.json`), `scripts/gen_site_schema.py`, `docs/openapi/site-builder.yaml`, `docs/features/site-builder.md`, `tests/test_site_builder*.py` |
| infrastructure | `site-builder/**` (incl. state machine definition), `site-builder.tf`, `network/api-gateway/site-builder-routes.tf` |
| admin-front-end | `src/features/site-builder/**` (`WebbplatsPage.tsx` and the editor) |
| booqy-console | `api/src/app/features/site_builder.py`, `api/tests/test_feature_site_builder.py`, `web/src/features/site-builder/**` (`SiteBuilderSection.tsx`) |
| customer-front-end | `packages/site-kit/src/features/site-builder/**` (`PreviewPage.tsx`, `BuilderPage.tsx`, block renderers, generated schema types), `render-lambda/**` (own `package.json`, not a root workspace; if it must be one, ask the orchestrator) |

The template repo workflow change for the custom-code tier is the owner's
`.github`: B writes the snippet into `docs/features/site-builder.md`.

### C. Guest CRM (`guest-crm`)

| Repo | Owns |
|---|---|
| application | `functions/guest-crm/**`, `functions/guest-crm-sync/**`, `shared/features/guest_crm/**`, `docs/openapi/guest-crm.yaml`, `docs/features/guest-crm.md`, `tests/test_guest_crm*.py` |
| infrastructure | `guest-crm/**`, `guest-crm.tf`, `network/api-gateway/guest-crm-routes.tf` |
| admin-front-end | `src/features/guest-crm/**` (`GasterPage.tsx`, `SegmentsPanel.tsx`, `SegmentAudienceOptions.tsx`, `GuestBadge.tsx`) |
| booqy-console | nothing (generic checkbox only) |
| customer-front-end | nothing |

### D. Google Business Profile (`google-business`)

| Repo | Owns |
|---|---|
| application | `functions/google-business/**`, `functions/google-business-jobs/**`, `shared/features/google_business/**`, `shared/google_business_real.py`, `docs/openapi/google-business.yaml`, `docs/features/google-business.md`, `tests/test_google_business*.py` |
| infrastructure | `google-business/**`, `google-business.tf`, `network/api-gateway/google-business-routes.tf` |
| admin-front-end | `src/features/google-business/**` (`GoogleProfileCard.tsx`, `OmdomenTab.tsx`) |
| booqy-console | `api/src/app/features/google_business.py`, `api/tests/test_feature_google_business.py`, `web/src/features/google-business/**` (`GoogleBusinessTenantSection.tsx`) |
| customer-front-end | nothing |

### E. Gift cards (`gift-cards`)

| Repo | Owns |
|---|---|
| application | `functions/gift-cards/**`, `shared/features/gift_cards/**`, `docs/openapi/gift-cards.yaml`, `docs/features/gift-cards.md`, `tests/test_gift_cards*.py` |
| infrastructure | `gift-cards/**`, `gift-cards.tf`, `network/api-gateway/gift-cards-routes.tf` |
| admin-front-end | `src/features/gift-cards/**` (`PresentkortPage.tsx`, `KassaGiftCardButton.tsx`) |
| booqy-console | nothing |
| customer-front-end | `packages/site-kit/src/features/presentkort/**` (`PresentkortPage.tsx`, `SaldoPage.tsx`, `GiftCardField.tsx`) |

Kassa, checkout, Stripe webhook, Bokföring and receipt changes for gift
cards are hotspot work done in Run 0 (section 3); E implements the hook
answers only.

### F. Waitlist (`waitlist`)

| Repo | Owns |
|---|---|
| application | `functions/waitlist/**`, `shared/features/waitlist/**`, `docs/openapi/waitlist.yaml`, `docs/features/waitlist.md`, `tests/test_waitlist*.py` |
| infrastructure | `waitlist/**`, `waitlist.tf`, `network/api-gateway/waitlist-routes.tf` |
| admin-front-end | `src/features/waitlist/**` (`QueuePanel.tsx`, `WaitlistSettingsCard.tsx`); read-only reuse of `src/features/layout-editor` components |
| booqy-console | nothing |
| customer-front-end | `packages/site-kit/src/features/ko/**` (`KoPage.tsx`, `JoinQueueLink.tsx`) |

### G. Social posting (`social-posting`)

| Repo | Owns |
|---|---|
| application | `functions/social-posting/**`, `shared/features/social_posting/**`, `docs/openapi/social-posting.yaml`, `docs/features/social-posting.md`, `tests/test_social_posting*.py` |
| infrastructure | `social-posting/**`, `social-posting.tf`, `network/api-gateway/social-posting-routes.tf` |
| admin-front-end | `src/features/social-posting/**` (`InlaggTab.tsx`, `ShareDishAction.tsx`) |
| booqy-console | nothing |
| customer-front-end | nothing |

G may not edit A's files, including `shared/meta_graph.py` and
`shared/meta_graph_real.py`; G's port methods exist from Run 0.

### H. Personalliggare (`personalliggare`)

| Repo | Owns |
|---|---|
| application | `functions/personalliggare/**`, `shared/features/personalliggare/**`, `docs/openapi/personalliggare.yaml`, `docs/features/personalliggare.md`, `tests/test_personalliggare*.py` |
| infrastructure | `personalliggare/**` (both tables, resource policy), `personalliggare.tf`, `network/api-gateway/personalliggare-routes.tf` |
| admin-front-end | `src/features/personalliggare/**` (`PersonalliggarePage.tsx`) |
| booqy-console | `api/src/app/features/personalliggare.py`, `api/tests/test_feature_personalliggare.py`, `web/src/features/personalliggare/**` (`ExportLedgerSection.tsx`) |
| customer-front-end | nothing |

H's copy check test lives in `application/tests/test_personalliggare_copy.py`
and only reads the other repos.

### I. Fortnox and Visma (`accounting-sync`)

| Repo | Owns |
|---|---|
| application | `functions/accounting-sync/**`, `shared/features/accounting_sync/**` (incl. `FortnoxTarget`, `VismaTarget` implementing `shared.accounting_export.AccountingTarget`), `shared/fortnox_real.py`, `shared/visma_real.py`, `docs/openapi/accounting-sync.yaml`, `docs/features/accounting-sync.md`, `tests/test_accounting_sync*.py` |
| infrastructure | `accounting-sync/**` (table, FIFO queues, schedule, app secrets), `accounting-sync.tf`, `network/api-gateway/accounting-sync-routes.tf` |
| admin-front-end | `src/features/accounting-sync/**` (`DirektbokforingCard.tsx`) |
| booqy-console | nothing |
| customer-front-end | nothing |

### J. Margin per dish (`dish-margin`)

| Repo | Owns |
|---|---|
| application | `functions/dish-margin/**`, `shared/features/dish_margin/**`, `shared/dish_margin.py` (Run 0 stub, J owns it from Run 3), `docs/openapi/dish-margin.yaml`, `docs/features/dish-margin.md`, `tests/test_dish_margin*.py` |
| infrastructure | `dish-margin/**`, `dish-margin.tf`, `network/api-gateway/dish-margin-routes.tf` |
| admin-front-end | `src/features/dish-margin/**` (`DishCostField.tsx`, `MarginChart.tsx`, `signals.ts`) |
| booqy-console | nothing |
| customer-front-end | nothing |

### K. Events and tickets (`events-tickets`, addendum)

| Repo | Owns |
|---|---|
| application | `functions/events-tickets/**`, `shared/features/events_tickets/**` (incl. `passes.py` for Apple/Google Wallet signing, `qr.py`, `series.py`), `docs/openapi/events-tickets.yaml`, `docs/features/events-tickets.md`, `tests/test_events_tickets*.py`, `tests/fixtures/events_tickets/**` (test pass certificate) |
| infrastructure | `events-tickets/**`, `events-tickets.tf`, `network/api-gateway/events-tickets-routes.tf` |
| admin-front-end | `src/features/events-tickets/**` (`EvenemangPage.tsx`, `EventEditor.tsx`, `InslappPage.tsx` (scanner and guest list, IndexedDB queue), `EventsStats.tsx`, `posterPrint.ts`, API client) |
| booqy-console | nothing (generic checkbox and the generic limits input) |
| customer-front-end | `packages/site-kit/src/features/evenemang/**` (`EvenemangPage.tsx`, `EvenemangDetaljPage.tsx`, `BiljettPage.tsx`, `TaEmotPage.tsx`) |

Stripe webhook routing for `metadata.kind = ticket`, the `insights.events`
call site, the `BokforingCard` "Biljetter" group and the `ticketSales*`
roles in `shared/accounting.py` are hotspot work batched for the Run 2
hotspot window; K implements the hook answers only. K reuses
`layout-editor` components read-only for table pick (as F does). K adds no
dependency to admin without the orchestrator's approval (scanner uses the
browser `BarcodeDetector` API with a typed fallback).

### L. AI phone agent (`phone-agent`, addendum)

| Repo | Owns |
|---|---|
| application | `functions/phone-agent/**`, `functions/phone-agent-call/**` (incl. its Dockerfile with the Lambda Web Adapter for the streaming turn endpoint), `functions/phone-agent-jobs/**`, `shared/features/phone_agent/**` (`agent.py` loop, `tools.py`, `copy.py` fixed Swedish/English sentences and the art. 50 text, `simulator.py` text-in/text-out harness, `calls.py` state machine, `metering.py`), `shared/voice_provider_real.py`, `shared/telephony_real.py`, `shared/agent_model_real.py`, `docs/openapi/phone-agent.yaml`, `docs/features/phone-agent.md`, `tests/test_phone_agent*.py` |
| infrastructure | `phone-agent/**` (table, bucket, three Lambdas, Function URL, alarms, secrets), `phone-agent.tf`, `network/api-gateway/phone-agent-routes.tf` |
| admin-front-end | `src/features/phone-agent/**` (`TelefonPage.tsx`, `CallsTab.tsx`, `CallDetail.tsx`, `CallbacksTab.tsx`, `SettingsWizard.tsx` ("Så svarar vi i telefon"), `SimulatorPanel.tsx`, `CallbacksPanel.tsx`, `CallBadge.tsx`, API client) |
| booqy-console | `api/src/app/features/phone_agent.py`, `api/tests/test_feature_phone_agent.py`, `web/src/features/phone-agent/**` (`PhoneAgentTenantSection.tsx`, `PhoneAgentSettingsCard.tsx`) |
| customer-front-end | nothing |

L may not edit A's `shared/bedrock.py` or `shared/bedrock_real.py`; the
agent loop uses its own `AgentModel` port. L invokes the existing
reservation, menu and site-config Lambdas (ADR-L tool table) and never
edits them; a needed change there (for example a `phone=` filter on the
reservation list, or a `source` field on created reservations) is reported
to the orchestrator for the Run 2 hotspot window. The `billing.usage`
caller in platform-tenants and the two invoice lines are hotspot work; L
answers the hook. The privacy notice paragraph "Telefonassistent" is a
hotspot (`shared/privacy_notice.py`), wording **[NEEDS YOUR OK]**.

### Overlap check

Every owned path above contains the feature's own id or snake name, except
the client real files (one owner each: meta and bedrock A, google_business
D, fortnox and visma I, voice_provider, telephony and agent_model L) and
`shared/dish_margin.py` (J). No path appears under two features. K and L
share no path: K never touches `phone-agent*` or `phone_agent*`, L never
touches `events-tickets*` or `events_tickets*`; the two new admin slots on
`BokningarPage` are L's and the one on `StatistikPage` is K's; the
console files are L's only.

## 2. Non-feature owners

| Owner | Paths |
|---|---|
| Brand guardian | `customer-front-end/packages/brand/**`; `infrastructure/docs/design/**` (INVENTORY.md, DESIGN.md, brand ADR); the brand lint config and script files it creates (named in DESIGN.md). In Runs 1-2 only the single brand guardian builder on `build/brand-additions` edits them. Addendum: the same single builder adds the variants K and L need (section 6.6) on `build/run-0-addendum-kl` in customer-front-end. |
| Owner (human) | every `.github/**` in every repo (agents give a snippet or `sed` line), OIDC/deploy roles, `sites/main.tf` `deploy_boundary`, `prod.tfvars` values beyond Run 0's additions |
| Orchestrator / integrator | `infrastructure/docs/build/**`, `infrastructure/docs/adr/**`, every shared hotspot below, `ROUTES.md` regeneration, merges |

### Brand guardian, Run 0 only (branch `build/run-0-brand`)

Besides `customer-front-end/packages/brand/**` and `infrastructure/docs/design/**`
plus `infrastructure/docs/adr/ADR-BRAND-sharing.md`, the brand guardian may
edit in Run 0, for the one-screen pilots and the package wiring:
customer-front-end root `package.json` and `package-lock.json` and the
Kontakt pilot (`src/features/kontakt/KontaktPage.tsx`) and `src/main.tsx`
(imports `@booqy/brand/styles.css`); admin-front-end
`package.json`, `package-lock.json`, `vendor/booqy-brand-*.tgz`,
`src/main.tsx`, `src/shared/motion/BusyBar.tsx`, `src/shared/brand.css`;
booqy-console/web `package.json`, `package-lock.json`,
`vendor/booqy-brand-*.tgz`, `src/main.tsx`, `src/components/BusyBar.tsx`,
`src/styles.css`; booqy-website `site/assets/brand/**`, the tour progress
markup in the six pages that have the tour and `site/assets/booqy.{css,js}`.
In Runs 1-3 only a single brand guardian builder on `build/brand-additions`
edits `packages/brand`; Run 3 consolidation agents own their app.

## 3. Shared hotspots (orchestrator only; changed in Run 0 only)

After Run 0 these are frozen for Runs 1-3. A needed change is reported,
batched by the orchestrator and made between runs, never by a feature.

### application

| Path | Run 0 change |
|---|---|
| `contracts/booqy.yaml`, `scripts/gen_contracts.py`, `shared/contracts.py` (generated), `tests/test_contracts.py` | new (task AP1); addendum additions (section 6.1) |
| `shared/voice_provider.py`, `shared/telephony.py`, `shared/agent_model.py` and the three `*_real.py` skeletons (then owned by L) | new in the addendum (section 6.1) |
| `shared/tenant.py` | FEATURES, limits, any-of features (AP2) |
| `shared/events.py`, `shared/feature_hooks.py`, `tests/hooks_fake.py` | new (AP4, AP5) |
| `shared/meta_graph.py`, `shared/google_business.py`, `shared/fortnox.py`, `shared/visma.py`, `shared/bedrock.py`, `shared/external_client.py` and the five `*_real.py` skeletons (then owned per section 1) | new (AP6) |
| `functions/tenant-site-config/**` | AP3 |
| `functions/guest-privacy/**` | AP7 |
| `functions/tenant-purge/**` | AP8 |
| `functions/notification/**` | AP9 |
| `functions/stripe-webhook/**` | AP10 |
| `functions/payment-intent/**`, `functions/webhook-payment-intent/**` | AP11 |
| `functions/kassa/**`, `shared/kassa.py`, `shared/kassa_receipt.py`, `shared/control_system.py` | AP12 |
| `functions/accounting/**`, `shared/accounting.py`, `shared/accounting_export.py` | AP13 |
| `functions/insights/**`, `functions/insights-rollup/**`, `shared/insights.py`, `shared/dish_margin.py` (stub) | AP14 |
| `functions/marketing/**`, `functions/marketing-send/**`, `functions/marketing-public/**`, `functions/marketing-sync/**`, `shared/marketing*.py` | AP15 |
| `docs/openapi.yaml`, `docs/openapi/README.md`, `tests/test_openapi.py` | AP16 |
| `tests/tenant_support.py` | AP17 |
| `shared/privacy_notice.py` | AP18 |
| `functions/data-retention/**`, `shared/retention.py`, `shared/consent.py`, `shared/messages.py` | unchanged in Run 0, still hotspots (frozen) |
| `requirements.txt`, `requirements-dev.txt`, `shared/features/__init__.py` | AP1, AP5 |

### infrastructure

| Path | Run 0 change |
|---|---|
| `variables.tf`, `dev.tfvars`, `prod.tfvars`, `storage/dynamodb/tenant/**` | IN2 |
| `external-clients.tf` | IN1 |
| `events.tf`, `events/**` | IN3 |
| the ten `<id>/` stubs and `<id>.tf` (then owned per section 1) | IN4; addendum adds `events-tickets/`, `phone-agent/` and their root files (section 6.2) |
| `config.tf`, `outputs.tf` | IN5 |
| `network/api-gateway/main.tf`, `variables.tf`, `outputs.tf`, `feature-routes.tf`, the ten `<id>-routes.tf` stubs (then owned), `generate_routes.py`, `ROUTES.md` | IN6 |
| `security/iam/feature-hooks/**` | IN7 |
| `compute/lambda/notification/**` | IN8 |
| `sites/**`, `payments/stripe/**`, `marketing/**`, `kassa/**`, `accounting/**` | frozen (no Run 0 change except IN7 attaching by role name) |

### admin-front-end

| Path | Run 0 change |
|---|---|
| `src/shared/contracts.ts` (generated), `src/shared/tenant.ts`, `src/shared/slots.tsx` | AD1, AD2, AD5 |
| `src/shared/AdminLayout.tsx`, `src/App.tsx`, `src/pages.ts` | AD3, AD4 |
| `src/shared/storageRegistry.ts` | none in Run 0; addendum adds `EVENT_SCAN_KEY_PREFIX` (section 6.3), then frozen again |
| `src/features/guide/steps.ts` | AD8; addendum adds two steps |
| host pages: `src/features/marknadsforing/{MarknadsforingPage,OverviewTab,SubscribersTab,CampaignsTab}.tsx`, `src/features/installningar/{InstallningarPage,BokforingCard}.tsx`, `src/features/installningar/accountingApi.ts`, `src/features/bokningar/BokningarPage.tsx`, `src/features/kassa/KassaPage.tsx`, `src/features/meny/{MenyPage,DishModal}.tsx`, `src/features/statistik/{StatistikPage.tsx,insights.ts}` | AD6, AD7 |

### booqy-console

| Path | Run 0 change |
|---|---|
| `api/src/app/tenants.py`, `api/src/app/handler.py`, `api/src/app/contracts.py` (generated), `api/src/app/features/__init__.py`, `api/src/app/features/_forward.py` | CO2, CO3 |
| `web/src/types.ts`, `web/src/contracts.ts` (generated), `web/src/slots.tsx` | CO1, CO4, CO6 |
| `web/src/pages/{TenantPage,NewTenantPage,SettingsPage}.tsx`, `web/src/components/WebsiteTab.tsx` | CO5, CO6 |
| `web/src/storageRegistry.ts` | none (frozen) |

Addendum console hotspot changes: `web/src/pages/TenantPage.tsx`
Integrations tab condition gains `phoneAgent`; `web/src/slots.tsx` two
slot ids; `api/src/app/features/phone_agent.py` stub with `ROUTES = {}`
(then owned by L); `_forward.py` unchanged (section 6.4).

### customer-front-end

| Path | Run 0 change |
|---|---|
| `packages/site-kit/src/shared/{site.ts,contracts.ts,slots.tsx,storageRegistry.ts}` | CU1, CU2, CU3, CU5; addendum: regenerated contracts, `TICKET_PURCHASE_KEY` (section 6.5) |
| `packages/site-kit/src/pages.ts`, `packages/site-kit/src/index.ts`, `src/App.tsx`, the site nav layout file (`CustomerLayout.tsx`) | CU4 |
| `packages/site-kit/src/features/boka/**` and `packages/site-kit/src/features/bestall/**` host files | CU5 (slot insertion only) |
| root `package.json`, `package-lock.json` | frozen |

## 4. Run 0 scaffolding work order

One implementer per repo. Order: **application first** (owns the generator),
then infrastructure, admin-front-end, booqy-console, customer-front-end in
parallel. Each frontend implementer generates its own contracts file with
`python ../application/scripts/gen_contracts.py --only <target>` (targets:
`application`, `console-api`, `admin`, `console-web`, `site-kit`). Nothing
in Run 0 changes behaviour for any tenant: every new key is false, every
hook call is gated or finds no deployed target, every new UI is hidden.
All existing tests must pass unchanged; new tests are listed per task.

Gates per repo before hand-off: application `python -m pytest -q -n auto`;
infrastructure `terraform fmt -check -recursive -diff` and
`terraform init -backend=false && terraform validate`, plus the existing
`python3 -m unittest discover` suites; admin `npm run lint`, `npx tsc -b`,
`NODE_OPTIONS=--no-experimental-webstorage npm test`, `npm run build`;
console `npm run typecheck`, `npm test`, `npm run build` in `web/`, `python
-m pytest` in `api/`; customer `npm run lint`, `npm run typecheck -w
@booqy/site-kit`, tests, `npm run build`; and `gen_contracts.py --check`.
UI checked at mobile, tablet and desktop, light and dark (placeholders and
the console Plan tab).

### 4.1 application (18 tasks)

| # | Files | Behaviour | Tests |
|---|---|---|---|
| AP1 | new `contracts/booqy.yaml`, `scripts/gen_contracts.py`, `shared/contracts.py`; `requirements-dev.txt` adds `PyYAML` | YAML exactly per CONTRACTS.md sections 1-10; generator writes the five targets of 1.2 (`--only`, `--check`); deterministic output (sorted where order is not meaningful) | `tests/test_contracts.py`: regenerate equals file; existing siblings equal; self-consistency rules of 1.2 |
| AP2 | `shared/tenant.py` | `FEATURES = contracts.FEATURE_KEYS` (fixes "lacks marketing"); `limit(tenant_row, name)` (missing -> contract default, unknown name raises); `for_jwt`/`for_public` `feature=` accepts a tuple = any of; `require_feature` unchanged for a string | any-of on/off, limit default 0, unknown limit raises, existing tenant tests unchanged |
| AP3 | `functions/tenant-site-config/app.py` | `_FEATURES = contracts.SITE_CONFIG_FEATURES` (existing five + `giftCards`, `waitlist`, `siteBuilder`; kassa stays out, comment says why); `tenant.site` and `locations[].waitlist` per CONTRACTS.md 7 | fields absent when off or attribute missing, present when both; foreign tenant unchanged |
| AP4 | new `shared/events.py` | `publish(feature_id, detail_type, detail)`: unknown source/type or missing required field raises `ValueError`; extra fields not in the contract raise; adds `occurredAt`, `version: 1`; `PutEvents` to `EVENT_BUS_NAME` (missing env raises); returns the event id | validation cases with moto `events`, or a stubbed client |
| AP5 | new `shared/feature_hooks.py`, `shared/features/__init__.py` (empty), `tests/hooks_fake.py` | envelope and `call()` per CONTRACTS.md 9.1; function name `<prefix><feature-id>`, qualifier `live`, prefix from `ENVIRONMENT`; targets from `contracts.HOOKS`; injectable invoker | not deployed -> skipped; FunctionError -> `HookFailed`; `ok: false` passed through; envelope shape |
| AP6 | new `shared/external_client.py` (`mode(env_var) -> "simulator" \| "real"`, prod refusal), `shared/meta_graph.py`, `shared/google_business.py`, `shared/fortnox.py`, `shared/visma.py`, `shared/bedrock.py` (port + Simulated + `client()`), `shared/{meta_graph,google_business,fortnox,visma,bedrock}_real.py` skeletons | per CONTRACTS.md 13 | per client: factory picks simulator, refuses it in prod, refuses unknown value; real skeleton raises `NotImplementedError`; simulator idempotent by name (Meta), refresh rotation (Fortnox/Visma), schema-shaped output (Bedrock), `fail=` injection |
| AP7 | `functions/guest-privacy/app.py` | export adds `features: {<feature-id>: items}` from `privacy.export`; erase calls `privacy.erase` after its own steps and adds counts; a `HookFailed` makes the whole call 503 (erase is re-runnable); logs counts only | fake hooks: merged export, erase counts, failure 503, not-deployed skipped; existing tests unchanged |
| AP8 | `functions/tenant-purge/app.py` | for each tenant being purged, after its current steps: `tenant.purge` with `locationIds` and `round`; the tenant is marked purged only when every deployed target returns `done: true`; existing `tenant_purge_tables` and steps untouched | not done -> next round calls again; done -> purged; failure reported in the summary mail, not fatal for other tenants |
| AP9 | `functions/notification/app.py` | new entry: `{"notice": {...}}` (CONTRACTS.md 9.4) handled before the stream loop; validates kind format, channel, `to`; uses existing `_send_email` / `_send_sms` (sender name, prefixes, outbox, part counting with `kind`); never logs `to` or text | email and SMS via outbox in dev; bad payload logged and dropped; stream path unchanged |
| AP10 | `functions/stripe-webhook/app.py` | events whose object `metadata.kind == "giftcard"` (payment_intent.succeeded, payment_intent.payment_failed, charge.refunded, charge.dispute.closed) go to `stripe.event` and return its result; nothing else changes | fake hook receives the event; other kinds untouched; hook failure -> 500 so Stripe retries |
| AP11 | `functions/payment-intent/app.py`, `functions/webhook-payment-intent/app.py` | `giftCardCode` in `_FIELDS`; `giftCards` off -> 400 `gift_cards_off`; on -> `checkout.giftcard` `reserve`; order stores `giftCard{cardId, last4, debitedOre}`; Stripe amount = total - debited; fully covered -> no Stripe call, order confirmed; `ok: false` codes mapped to 409; expiry/failure in the webhook calls `reverse` once (conditional on the order's `giftCard.reversedAt`) | off 400; partial; full cover; reverse once on replay; existing checkout tests unchanged |
| AP12 | `functions/kassa/app.py`, `shared/kassa.py`, `shared/kassa_receipt.py`, `shared/control_system.py` | bill payment `{kind: "giftcard", paymentId}` allowed when `giftCards` and `kassa` on: `kassa.giftcard verify` gives amount and card; stored as `{paymentId, method: "Presentkort", amount, last4, cardId}`; undo before receipt calls `reverse`; receipt line "Presentkort ****1234, kvar 150 kr"; control system reports it as the voucher payment means; if `control_system.py` has no voucher means, stop and report to the orchestrator (legal check, blocks E) | off -> refused; verify/undo; receipt text; journal hash chain still verifies; existing kassa tests unchanged |
| AP13 | `shared/accounting.py`, `functions/accounting/app.py` | roles `giftCardLiability` (2421, "Ej inlösta presentkort") and `giftCardBreakage` (3990, "Övriga ersättningar och intäkter") accepted in settings; `#KONTO` and names list them only when a line uses them, so SIE/CSV output for tenants without gift cards stays byte-identical; Kassa method `Presentkort` debits `giftCardLiability`; `location_events` appends `accounting.events` results (location row's `tenantId`) | SIE byte-identical regression; balanced entry with a fake gift card sale, redemption and breakage; hook failure -> export 503 |
| AP14 | `shared/insights.py`, `functions/insights/app.py`, new `shared/dish_margin.py` | `MONEY_FIELDS` and `without_money` also drop `cost`, `margin`, `marginPct`, `missingCost`, `targetMarginPct` (dishes and summary); owner with `dishMargin` on -> `insights.dishCosts` then `dish_margin.apply(summary, costs)` (stub returns summary) | staff body has none of the five (raw JSON); off -> response identical to today |
| AP15 | `functions/marketing/app.py`, `functions/marketing-send/app.py` (and `shared/marketing*.py` as needed) | audience `{type: "segment", exportId}` accepted only with `guestCrm` on; `describe` on save; `page` while sending; `consent.may_send` still per recipient | off refused; send skips a withdrawn id; existing audiences unchanged |
| AP16 | `tests/test_openapi.py`, new `docs/openapi/README.md`, `docs/openapi.yaml` | merge fragments, duplicate check, per-fragment operations == handler `ROUTES` (CONTRACTS.md 15); document `giftCardCode`, insights margin fields (owner only), guest export `features`, site-config `tenant.site`, `locations[].waitlist`, three new feature flags | merged doc valid; a test fragment with a missing route fails (use a temp dir) |
| AP17 | `tests/tenant_support.py` | per CONTRACTS.md 16; `ALL_FEATURES` values unchanged (decision: fixing it would turn `kassa`/`marketing` on in hundreds of legacy tests) and a comment saying so | helpers used by AP2/AP3 tests |
| AP18 | `shared/privacy_notice.py` | template gains two paragraphs, included only when the feature is on: "Gästregister" (guestCrm) and "Kö" (waitlist); wording marked for legal review | paragraphs absent when off |

### 4.2 infrastructure (9 tasks)

| # | Files | Behaviour | Check |
|---|---|---|---|
| IN1 | new `external-clients.tf` | the six variables of CONTRACTS.md 12.1 with descriptions and validation | validate |
| IN2 | `variables.tf`, `dev.tfvars`, `prod.tfvars`, `storage/dynamodb/tenant/**` | `plans` object gains `limits = optional(map(number), {})` + validation; both tfvars rows gain the ten keys `false` and `limits = { siteBuilderAiEditsPerMonth = 0 }`; plan item writes `limits`; Stripe billing catalog unaffected | plan item shape in a `terraform console` check or the module's tests; fmt |
| IN3 | new `events.tf`, `events/{main,variables,outputs}.tf`, `events/README.md` | `aws_cloudwatch_event_bus` `${prefix}booqy-events`, tag `Environment`; outputs `bus_name`, `bus_arn` | validate |
| IN4 | ten `<id>/{main,variables,outputs}.tf` + `README.md`, ten `<id>.tf` | zero resources; `variable "environment"`; `output "wiring"` exact shape of CONTRACTS.md 12.2; README states purpose, ADR, run and "no resources until Run N" | validate; plan shows no change from these |
| IN5 | `config.tf`, `outputs.tf` | 14 ECR modules (CONTRACTS.md 12.2) and their `ecr_repository_urls` entries; `local.feature_wiring = [module.meta_ads.wiring, ...]`; merged into `module "lambda_releases"` `functions`, `local.tenant_aware_role_names`, `module "tenant_context_policy"` `staff_check_role_names`; `module "api_gateway"` gets `feature_integrations` | validate; CI's ECR guard loop logic satisfied (every `*_ecr` in outputs) |
| IN6 | `network/api-gateway/{main.tf,variables.tf,feature-routes.tf,generate_routes.py,ROUTES.md}`, ten `<id>-routes.tf` | `variable "feature_integrations"` (map of `{function_name, invoke_arn}`); `feature-routes.tf` concatenates the ten `*_routes` locals, creates one AWS_PROXY integration (payload 2.0) and lambda permission (alias qualifier) per feature, and the routes with the authorizer per `auth`; precondition: jwt/public route without integration fails; `throttle = "public"` route_settings in `main.tf`; generator reads the new files | validate; `python3 generate_routes.py` output unchanged with empty lists |
| IN7 | new `security/iam/feature-hooks/` + module call in `config.tf` | inline policies of CONTRACTS.md 14 (rows 1-10) attached by role name, `Sid` per hook, resources = exact `:live` ARNs; **IAM change: owner to approve** before Run 0 merges | validate; plan diff reviewed by the owner |
| IN8 | `compute/lambda/notification/**` | `aws_lambda_function_event_invoke_config` on the `live` alias, `maximum_retry_attempts = 0` | validate |
| IN9 | all | `terraform fmt -recursive`; existing unittest suites | gates |

### 4.3 admin-front-end (9 tasks)

| # | Files | Behaviour | Tests |
|---|---|---|---|
| AD1 | `src/shared/contracts.ts` | generated (`--only admin`) | typecheck |
| AD2 | `src/shared/tenant.ts` | `entitlements.limits?: Partial<Record<LimitKey, number>>`; `hasFeature(tenant, key \| key[])` (array = any of); `LOCAL_DEMO_TENANT` stays `features: {}` | hasFeature cases |
| AD3 | `src/shared/AdminLayout.tsx` | `NavItem.feature: FeatureKey \| FeatureKey[]`; filter uses `hasFeature`; four items and the Marknadsföring any-of per CONTRACTS.md 8.1 | new `AdminLayout.test.tsx`: items hidden when off, shown when on, ownerOnly hidden for staff |
| AD4 | `src/pages.ts`, `src/App.tsx`, four placeholder pages in `src/features/{personalliggare,guest-crm,gift-cards,site-builder}/` | routes `/personalliggare`, `/gaster`, `/presentkort`, `/webbplats`; placeholder per CONTRACTS.md 8.1 (guard, Swedish copy, brand components only) | placeholder guard test per page |
| AD5 | new `src/shared/slots.tsx`; placeholder components (default export returning `null`) at every file path of CONTRACTS.md 8.2; `src/features/dish-margin/signals.ts` returning `[]` | `SLOT_LOADERS: Record<AdminSlotId, () => Promise<{default: ComponentType<any>}>>` (missing id fails typecheck); `<Slot id props>` gating per 8.2 | slot hidden when off / staff on ownerOnly, rendered when on |
| AD6 | host pages listed in section 3 | insert each `<Slot>` at its place; Marknadsföring tab list built from `TABS` + the three slot tabs, existing tabs only with `marketing`; default tab = first visible | MarknadsforingPage: tenant with only `metaAds` sees "Annonser" only; existing tests unchanged |
| AD7 | `src/features/installningar/{BokforingCard.tsx,accountingApi.ts}`, `src/features/statistik/insights.ts` | Presentkort account group shown only with `giftCards`; `ACCOUNT_ROLES` gains the two roles; `signals()` appends `dishMarginSignals(data)` | BokforingCard hidden/shown group; signals unchanged with stub |
| AD8 | `src/features/guide/steps.ts` | four steps (CONTRACTS.md 8.1), skipped when the nav item is hidden | guide test |
| AD9 | none | storage registry unchanged (no new keys); gates, UI check of placeholders | `storageRegistry.test.ts` passes |

### 4.4 booqy-console (6 tasks)

| # | Files | Behaviour | Tests |
|---|---|---|---|
| CO1 | `api/src/app/contracts.py`, `web/src/contracts.ts` | generated (`--only console-api`, `--only console-web`) | typecheck, import |
| CO2 | `api/src/app/tenants.py` | `_overrides`: `features` keys must be in `FEATURE_KEYS` (400 `overrides.features`), `limits` map validated against `LIMITS` bounds (400 `overrides.limits.<k>`); `_entitlements` copies plan `limits` and applies override limits; `list_plans`/`get_plan` return `limits` | unknown key 400; limit bounds; plan copy; existing plan tests unchanged |
| CO3 | `api/src/app/handler.py`, new `api/src/app/features/{__init__,_forward}.py`, four stubs `features/{meta_ads,site_builder,google_business,personalliggare}.py` with `ROUTES = {}` | handler merges each module's `ROUTES` (duplicate key raises at import); `_forward.forward(feature_id, op)` returns a handler that invokes `<prefix><feature-id>:live` with the `platform` hook (CONTRACTS.md 9.3), maps `status`/`body`, writes the audit action for writes | merge, duplicate refusal, forward with a stubbed Lambda client, audit row |
| CO4 | `web/src/types.ts` | `Entitlements.limits?`, `Plan.limits?`, `NewTenantInput.overrides` widened to what the pages send (`maxLocations?`, `features?`, `limits?`) | typecheck |
| CO5 | `web/src/pages/{TenantPage,NewTenantPage}.tsx` | checkboxes over `FEATURE_KEYS` with `FEATURE_LABELS[k].en`; "AI site edits per month" input; overrides include changed limits; Overview row labels | NewTenantPage and Plan tab tests for labels and limit override |
| CO6 | new `web/src/slots.tsx`, `web/src/pages/{TenantPage,SettingsPage}.tsx`, `web/src/components/WebsiteTab.tsx`; placeholder components at the paths of CONTRACTS.md 8.3 | Integrations tab (visible per 8.3), slots in Website, offboard and Settings | tab hidden when both features off; slot renders placeholder |

### 4.5 customer-front-end (6 tasks)

| # | Files | Behaviour | Tests |
|---|---|---|---|
| CU1 | `packages/site-kit/src/shared/contracts.ts` | generated (`--only site-kit`) | typecheck |
| CU2 | `packages/site-kit/src/shared/site.ts` | `SiteConfig.tenant.features` typed `Record<SiteFeatureKey, boolean>`; `tenant.site?: SiteBuilderState`; `SiteLocation.waitlist?: LocationWaitlist`; export the types from `index.ts` | typecheck; existing tests |
| CU3 | `packages/site-kit/src/shared/storageRegistry.ts` | constants and entries of CONTRACTS.md 10 | `storageRegistry.test.ts` passes (all nödvändig, described) |
| CU4 | `packages/site-kit/src/pages.ts`, `index.ts`, `src/App.tsx`, `CustomerLayout.tsx`; placeholder pages in `packages/site-kit/src/features/{presentkort,ko,site-builder}/` | routes and `sitePages` keys of CONTRACTS.md 8.4, gated like existing routes (off = not routed, falls to the existing not-found); Presentkort nav link when on; builder catch-all only when `tenant.site.mode === 'builder'` and `version > 0` | `App.test.tsx`: routes absent when off, present when on |
| CU5 | new `packages/site-kit/src/shared/slots.tsx`; host edits in `features/boka` and `features/bestall`; placeholder `JoinQueueLink.tsx`, `GiftCardField.tsx` | same `<Slot>` pattern, gated on `useSite()` features (and the location's `waitlist.publicJoin` for `boka.full`) | slot hidden/shown |
| CU6 | none | gates; `src/storage.test.ts` still passes (no new script hosts) | gates |

### 4.6 booqy-website

0 tasks. No feature edits it; H's copy test only reads it.

### Task count

| Repo | Tasks |
|---|---|
| application | 18 |
| infrastructure | 9 |
| admin-front-end | 9 |
| booqy-console | 6 |
| customer-front-end | 6 |
| booqy-website | 0 |
| **Total** | **48** |

## 5. Extension points built in Run 0 (summary)

| Extension point | Built where | A feature adds only |
|---|---|---|
| Contract source + generated types | `application/contracts/booqy.yaml` | nothing (contract fixed for Runs 1-3) |
| Feature hooks (privacy export/erase, tenant purge, Stripe kind, checkout, Kassa, accounting events, insights costs, marketing segments, console forwards) | `shared/feature_hooks.py` + callers | a `hook` branch in its own `functions/<id>/app.py` |
| Notification send entry | `functions/notification` | an invoke from its own Lambda |
| Event bus + publisher | `infrastructure/events/`, `shared/events.py` | `publish(...)` calls, its own rules |
| OpenAPI fragments | `docs/openapi/` + `tests/test_openapi.py` | `docs/openapi/<id>.yaml` |
| Terraform wiring output | `config.tf` merges `module.<snake>.wiring` | entries in its own module's `wiring` |
| Per-feature routes files | `network/api-gateway/feature-routes.tf` | `<id>-routes.tf` locals |
| ECR repos | `config.tf` (14, done) | nothing |
| Admin sidebar items, routes, slots | `AdminLayout.tsx`, `App.tsx`, `pages.ts`, `slots.tsx` | its own page and slot components |
| Console slots and route merge | `web/src/slots.tsx`, `api/src/app/handler.py` | its own section components and `features/<snake>.py` `ROUTES` |
| Site routes and slots | `pages.ts`, `App.tsx`, `slots.tsx` | its own site-kit feature folder |
| `/site-config` fields | `tenant-site-config` (pass-through of `PROFILE.site`, location `waitlist`) | the one attribute it writes |
| Storage keys | both registries (done) | imports of the constants |

### Deviation: contract changed between Run 1 and Run 2 (spec change 2026-11-04)

The row above says the contract is fixed for Runs 1-3. One recorded
exception: the owner's 2026-11-04 spec change (ADR-L decision 13,
CONTRACTS.md 17.1) edited these application paths between Run 1 and
Run 2, on `dev` via application#72 (draft) and the three frontend
companion PRs (generated files only: admin and console web gain the
`CounterOffer` type and the new hash, console API and site-kit only the
`CONTRACTS_HASH` line). After it merges every path returns to its usual owner.

| Repo | Path | Change | Why |
|---|---|---|---|
| application | `contracts/booqy.yaml` | enum `CounterOffer`, optional `PhoneCall.Ended.counterOffer` | CONTRACTS.md 17.1 |
| application | `shared/contracts.py` (generated) | `CounterOffer` Literal, `counterOffer?` on `PhoneCallEndedDetail`, `EVENTS`, `CONTRACTS_HASH` | regenerated from the YAML, `--check` clean |
| application | `tests/test_contracts.py` | expectations for the new enum and event field | self-consistency test must cover 17.1 |
| application | `shared/agent_model.py` | simulator counter-offer flow and sentences (sv, en) | port owned by Run 0 addendum (AK2), L owns it from Run 2; the simulator had to drive decision 13 before then |
| admin-front-end | `src/shared/contracts.ts` (generated) | `CounterOffer` type, `CONTRACTS_HASH` | regenerated from the YAML, `--check` clean |
| booqy-console | `web/src/contracts.ts` (generated) | `CounterOffer` type, `CONTRACTS_HASH` | regenerated from the YAML, `--check` clean |
| booqy-console | `api/src/app/contracts.py` (generated) | `CONTRACTS_HASH` only | regenerated from the YAML, `--check` clean |
| customer-front-end | `packages/site-kit/src/shared/contracts.ts` (generated) | `CONTRACTS_HASH` only | regenerated from the YAML, `--check` clean |

## 6. Run 0 addendum scaffolding work order (features K and L)

Same rules as section 4: one implementer per repo, application first
(generator), then the others in parallel; nothing changes behaviour for any
tenant (both keys false, limit 0, every hook gated "on or ever on" or finds
no deployed target, every new UI hidden); every existing test passes
unchanged; the gates of section 4 before hand-off. Branch
`build/run-0-addendum-kl` in every repo it touches, one PR per repo. Paths
listed here are the only ones the addendum builders may edit; after the
addendum merges they return to their section 1 or section 3 owner.

### 6.1 application (7 tasks)

| # | Files | Behaviour | Tests |
|---|---|---|---|
| AK1 | `contracts/booqy.yaml`, `scripts/gen_contracts.py`, the five generated targets | exactly CONTRACTS.md section 17: two features, one limit, five enums, two event sources, hook target changes and two new hooks, three clients, `siteConfig.tenantFeatures` + `events`, three admin and two console slots, the `storage.admin` map (generator emits `STORAGE_KEYS` into the admin contracts file), four console forward ops; `--check` clean in all five | `test_contracts.py` self-consistency (18 keys, 12 new, twelve purge targets, new storage map), regenerate-equals-file |
| AK2 | new `shared/voice_provider.py`, `shared/telephony.py`, `shared/agent_model.py` (port + Simulated + `client()` via `shared/external_client.mode`), `shared/voice_provider_real.py`, `shared/telephony_real.py`, `shared/agent_model_real.py` skeletons raising `NotImplementedError` | per CONTRACTS.md 13 (addendum rows): simulator idempotent agents by name, numbers in order and `number_unavailable`, scripted intent table in Swedish and English, `responses=`, `delay_ms`, `fail=` injection, webhook auth rules | factory picks simulator, refuses it in prod, refuses unknown; each simulator behaviour row; intent table covers every ADR-L scenario sentence in both languages |
| AK3 | `shared/tenant.py` | nothing to change (keys and limits come from the contract); confirm `limit()` handles the new name | existing tests plus one for the new limit default |
| AK4 | `functions/tenant-site-config/app.py` | `tenant.features.events` present (from `SITE_CONFIG_FEATURES`), nothing else | field present/absent |
| AK5 | `functions/stripe-webhook/app.py` | `metadata.kind == "ticket"` goes to `stripe.event` with target events-tickets (kind -> target map, `giftcard` unchanged) | fake hook receives it; `giftcard` path unchanged; unknown kind untouched |
| AK6 | `tests/tenant_support.py` | `NEW_FEATURES` twelve keys; `tenant_row(limits=)` accepts the new limit | helpers used by AK3/AK4 tests |
| AK7 | `docs/openapi/README.md`, `tests/test_openapi.py` | fragments `events-tickets.yaml`, `phone-agent.yaml` expected once the handlers exist (skip-if-absent like the others); `/site-config` documents `tenant.features.events` | merged doc valid |

Not in the addendum (Run 2 hotspot window, orchestrator): `insights.events`
call site, `billing.usage` call site and the invoice lines in
platform-tenants, `ticketSales*` roles in `shared/accounting.py`,
`privacy_notice.py` paragraph, the `events` group in `BokforingCard`.

### 6.2 infrastructure (6 tasks)

| # | Files | Behaviour | Check |
|---|---|---|---|
| IK1 | `external-clients.tf` | `voice_client`, `telephony_client`, `agent_model_client` (`simulator` default, validated), `phone_agent_model_id` (`""`) | validate |
| IK2 | `variables.tf`, `dev.tfvars`, `prod.tfvars` | `plans` validation accepts `phoneAgentMinutesPerMonth` 0-100000; both plan rows gain `events = false`, `phoneAgent = false`, `limits.phoneAgentMinutesPerMonth = 0`; new `phone_agent_location_price_sek`, `phone_agent_minute_price_sek` (default 0, **[NEEDS YOUR OK]** values stay 0 until set) | plan item shape; fmt |
| IK3 | new `events-tickets/{main,variables,outputs}.tf` + `README.md`, `phone-agent/{...}` + `README.md`, `events-tickets.tf`, `phone-agent.tf` | zero resources, `wiring` output of CONTRACTS.md 12.2, README names ADR, run and "no resources until Run 2" | validate; plan unchanged |
| IK4 | `config.tf`, `outputs.tf` | four ECR modules (`events_tickets_ecr`, `phone_agent_ecr`, `phone_agent_call_ecr`, `phone_agent_jobs_ecr`) and their `ecr_repository_urls` entries; `local.feature_wiring` merges twelve | validate; CI ECR guard |
| IK5 | `network/api-gateway/feature-routes.tf`, new `events-tickets-routes.tf`, `phone-agent-routes.tf`, `generate_routes.py` | two more empty route locals concatenated; generator reads them | validate; `generate_routes.py` output unchanged |
| IK6 | `security/iam/feature-hooks/**` | rows 11-16 of CONTRACTS.md 14 (guest-privacy, tenant-purge, stripe-webhook, accounting, insights, platform-tenants -> `events-tickets:live` / `phone-agent:live`); **IAM change: owner to approve** | validate; plan diff reviewed |

### 6.3 admin-front-end (5 tasks)

| # | Files | Behaviour | Tests |
|---|---|---|---|
| ADK1 | `src/shared/contracts.ts` | regenerated (`--only admin`), incl. `STORAGE_KEYS` | typecheck |
| ADK2 | `src/shared/AdminLayout.tsx`, `src/pages.ts`, `src/App.tsx`, placeholder pages `src/features/phone-agent/TelefonPage.tsx`, `src/features/events-tickets/EvenemangPage.tsx` | items "Telefon" (passet, after Personalliggare) and "Evenemang" (restaurangen, after Webbplats) per CONTRACTS.md 8.1, not ownerOnly; routes `/telefon`, `/telefon/samtal/:callId`, `/evenemang`, `/evenemang/:eventId`, `/evenemang/:eventId/inslapp/:occurrenceId` lazy to the feature folder; placeholder per 8.1 ("Den här delen är på väg.") | AdminLayout test: hidden when off, shown when on, visible to staff |
| ADK3 | `src/shared/slots.tsx`, placeholder components `src/features/phone-agent/{CallbacksPanel,CallBadge}.tsx`, `src/features/events-tickets/EventsStats.tsx`, host inserts in `src/features/bokningar/BokningarPage.tsx` and `src/features/statistik/StatistikPage.tsx` | three slot ids and loaders; placeholders return `null` | slot hidden/shown |
| ADK4 | `src/features/guide/steps.ts` | `nav-telefon`, `nav-evenemang` steps of CONTRACTS.md 8.1 | guide test |
| ADK5 | `src/shared/storageRegistry.ts` | `EVENT_SCAN_KEY_PREFIX` from `STORAGE_KEYS`, entry per CONTRACTS.md 10 (`kind: 'IndexedDB'`, category nödvändig) | `storageRegistry.test.ts` passes (extend the allowed kinds if the test enumerates them) |

### 6.4 booqy-console (3 tasks)

| # | Files | Behaviour | Tests |
|---|---|---|---|
| COK1 | `api/src/app/contracts.py`, `web/src/contracts.ts` | regenerated | typecheck, import |
| COK2 | `api/src/app/features/phone_agent.py` (`ROUTES = {}`) | merged by the handler like the four Run 0 stubs | merge test unchanged |
| COK3 | `web/src/slots.tsx`, `web/src/pages/{TenantPage,SettingsPage}.tsx`, placeholders `web/src/features/phone-agent/{PhoneAgentTenantSection,PhoneAgentSettingsCard}.tsx` | Integrations tab also visible with `phoneAgent`; slots `tenant.integrations.phoneAgent`, `settings.phoneAgent`; the Plan tab's limits input is generic over `LIMITS` (if Run 0 hard-coded one input, generalise it here) | tab visible with only `phoneAgent`; limit override for the new name |

### 6.5 customer-front-end (3 tasks)

| # | Files | Behaviour | Tests |
|---|---|---|---|
| CUK1 | `packages/site-kit/src/shared/contracts.ts`, `site.ts` | regenerated; `events` typed in `SiteFeatureKey` | typecheck |
| CUK2 | `packages/site-kit/src/pages.ts`, `index.ts`, `src/App.tsx`, `CustomerLayout.tsx`, placeholder pages in `packages/site-kit/src/features/evenemang/` | routes and `sitePages` keys of CONTRACTS.md 8.4 gated on `events`; "Evenemang" nav link when on; builder catch-all does not shadow them | `App.test.tsx`: absent when off, present when on |
| CUK3 | `packages/site-kit/src/shared/storageRegistry.ts` | `TICKET_PURCHASE_KEY` and entry | `storageRegistry.test.ts` |

### 6.6 brand guardian (1 task, customer-front-end `packages/brand`)

| # | Files | Behaviour | Tests |
|---|---|---|---|
| BRK1 | `customer-front-end/packages/brand/**`, `infrastructure/docs/design/{DESIGN,INVENTORY}.md` | `Bar variant="live"` (live call / recording indicator: pulsing dot, polite status text "Pågående samtal" / "Spelas in", reduced motion = static dot); `Chip` status component (`tone` info/success/warning/danger/neutral, text, optional icon) for ticket status and call outcome, listed in INVENTORY 3 as missing today; `Card surface="ticket"` (perforated edge, QR area, mono details, both themes); contrast tests for the new pairs; DESIGN.md catalogue rows | brand package tests, tokens drift test, contrast test, brand-lint exit 0 |

### Task count (addendum)

| Repo | Tasks |
|---|---|
| application | 7 |
| infrastructure | 6 |
| admin-front-end | 5 |
| booqy-console | 3 |
| customer-front-end | 3 (+1 brand) |
| booqy-website | 0 |
| **Total** | **25** |

### Ownership deviations (addendum, recorded in review)

The addendum builders edited these paths outside the lists of 6.1-6.6.
Each is a one-line, behaviour-neutral change the listed tasks needed; the
orchestrator accepted them in review. After the addendum merges every path
returns to its section 1, 2 or 3 owner as usual.

| Repo | Path | Task | Change | Why |
|---|---|---|---|---|
| admin-front-end | `src/features/cookies/CookiesPage.tsx` | ADK5 | `KIND_LABEL` gains `IndexedDB: 'Databas i webbläsaren (IndexedDB)'` | the `/cookies` page labels every `StorageKind`; the new `IndexedDB` kind would not typecheck or render without it |
| application | `shared/voice_provider_sim_recording.wav` (new, 1.6 kB) | AK2 | short silent WAV the voice-provider simulator returns as a call recording | the simulator needs a fixed recording payload; owned by L from Run 2 with `shared/voice_provider*.py` |
| application | `docs/openapi.yaml` | AK7 | `/site-config` documents `tenant.features.events` | the merged doc is the one the test validates; 6.1 listed only the README and the test (hotspot, AP16) |
| admin-front-end | `brand-lint.config.json` | ADK2/ADK3 | `block` gains `features/events-tickets/**`, `features/phone-agent/**` | the new feature folders get the same blocking glob as the ten Run 0 features |
| booqy-console | `web/brand-lint.config.json` | COK3 | `block` gains `features/phone-agent/**` | same, for the console placeholders |
| customer-front-end | `brand-lint.config.json` | CUK2 | `block` gains `features/evenemang/**` | same, for the guest placeholder pages |
| customer-front-end | `packages/site-kit/package.json`, `packages/site-kit/tsconfig.json`, `packages/site-kit/vite.config.ts`, root `package-lock.json` | Run 2 batch 1 (E, F site-kit pages; customer-front-end 2f43d25) | `dependencies` gains `"@booqy/brand": "0.1.0"`; `customConditions: ["@booqy/source"]` in tsconfig; `resolve.conditions` with `@booqy/source` in vite config; the lock file follows | the Kö and Presentkort pages use brand Bar and Button, so site-kit needs the brand package; tests and typecheck read the workspace source as the site does. DECISIONS.md 2026-11-04 records the npm alias and the brand CSS requirement before the first site-kit release |

The brand-lint config files are the brand guardian's (section 2); only the
blocking globs for the new feature folders were added, no rule changed. The
site-kit package files are the site-kit owner's (section 2); the Run 2 row
above is the one dependency and its resolution, no build output changed.

Rows missing from the Run 0 review (PIPELINE.md re-review note 2026-11-02), added now:

| Repo | Path | Task | Change | Why |
|---|---|---|---|---|
| booqy-console | `api/src/app/features/__init__.py` | CO2, CO3 | package marker for the feature modules (`_forward.py`, `phone_agent.py`) | the console API imports the feature modules as a package; section 3 listed `_forward.py` but not the marker (recorded in review, Run 0) |
| booqy-console | `web/src/pages/NewTenantPage.tsx` | CO5 | feature checkboxes over `FEATURE_KEYS` and generic limit inputs, as for `TenantPage.tsx` | listed in task CO5 but missing from the deviations table (recorded in review, Run 0) |
| application | edited existing `tests/test_*.py` files | AP-series, Run 0 | existing tests updated for the new features and contract hash, with no assertion removed or weakened | the review found these edits outside the test paths of 6.1; the file-by-file list is in the Run 0 PRs and was not reconstructed here |

