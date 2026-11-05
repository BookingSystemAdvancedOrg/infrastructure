# Build status

Ledger for the multi-agent build in `docs/build/PROMPTS.md`. Read this
first when a run starts or resumes; skip anything already verified or merged.

Last updated: 2026-11-04 (Run 2 batch 1: D, E, F, G built on `build/run-2-<feature>`, merged into `build/run-2-integration` and then to `dev`, awaiting the owner's go-ahead, see Run 2 batch 1 below; spec change after the Run 1 merges: ADR-L counter-offers settled and the ADR-A2 all-platform ads addendum written on draft PRs, see "Spec change 2026-11-04" below; Run 1 A, B1, C are on `dev` awaiting the owner's go-ahead).

## Spec change 2026-11-04 (owner instructions of 2026-11-04, Fable-led, no code behind a flag changes)

Branches `claude/spec-<repo>-*` with **draft PRs against `dev`** (listed
in PIPELINE.md); nothing merged, nothing to main, every feature stays
off.

- **L counter-offers (ADR-L decision 13, DECISIONS.md 2026-11-04 x2,
  CONTRACTS.md 1.3/5/6.L/13/14/17.1):** book if free; else the three
  closest same-day times on both sides; else the next day once, then a
  callback; a nearby table (adjacent pair within 1.0 m on the published
  floor plan, a larger table, a phone-only table) offered first at the
  requested time; the agent books through the staff manual route with
  `source: phone`, no server-side hold. Contract: enum `CounterOffer`,
  `PhoneCall.Ended.counterOffer?`, L4 `counterOffers{}`, L7/L8
  `counterOffer`; `booqy.yaml` changed and all five generated files
  regenerated (`gen_contracts.py --check` clean with the siblings beside
  it). Simulator (`shared/agent_model.py`) carries the counter-offer
  sentences and flow in Swedish and English;
  `tests/test_phone_agent_counter_offers.py` (30 cases, incl. the review
  fix: the next day is offered once per day the caller asks for) green;
  full application suite 4032 passed, 3 skipped; ruff: 3 pre-existing
  findings (not a CI gate). Unverified: the tool side (`offers()` from
  the real availability responses, the layout read) is Run 2 work.
- **A all platforms (ADR-A2, DECISIONS.md 2026-11-04):** platform
  adapter port behind the existing wizard; Meta then Google Ads then
  TikTok, Snapchat/Pinterest only on demand, others not suitable or
  not possible; per platform API access, approval, ad rules, cost
  stated with owner choices marked; spend confirmation enforced by
  `confirmedTotalSek`; schedules with limits and self-stop; first-time
  guide, daily view, plain tracking; brand only; **money-screen rule
  flagged** (owner-only/hidden-amount kept until the owner decides).
  Split A2 (Run 2) / A3 Google, A4 TikTok (Run 3); no run of its own.
  Contract rows are written at the Run 2 cut; nothing in `booqy.yaml`
  changed for A.

## Run 0: Foundations

**State: done and MERGED TO DEV (2026-11-01/02). All six Run 0 PRs merged by the owner: infrastructure#36, application#68, admin-front-end#21, booqy-console#11, customer-front-end#13, booqy-website#11. Run 0 addendum (K, L) in progress before Run 1.**

| Step | What | State |
|---|---|---|
| 1 | `docs/build/RULES.md` (operating rules, verbatim from PROMPTS.md) | done |
| 2 | Explore the codebase (5 Explore agents) | done, see `docs/build/EXPLORE-NOTES.md` |
| 3 | ADRs A-J in `docs/adr/` | done (10 ADRs; event source fixed as `booqy.<kebab feature id>`) |
| 4 | `docs/build/CONTRACTS.md` | done (contract source `application/contracts/booqy.yaml`; ADRs aligned) |
| 5 | `docs/build/OWNERSHIP.md` | done (48 scaffolding tasks, hotspot extension points) |
| 6 | Shared scaffolding (entitlements, plan matrix, sidebar slots, Terraform stubs, contract types, two-tenant fixtures, mock clients) | done: application phase 1 done (`d03c92f`, `e7a99cb`, `0849a0a`; 3545 tests pass); infrastructure done (`c0a7723`, fmt + validate + unit suites pass); application phase 2 committed (16 commits, 3726 passed, 1 skipped); fix loop round 1 done (`616405d` AP3 site-config features, `349c093` hook calls gated by entitlement so no existing path needs the IN7 IAM; 3734 passed, 1 skipped); admin done (`7cd2355`, `d172dd8`; 657 tests pass, segment audience typed without a cast); console done (`546c198`; api 173 passed, web 103 passed, build ok); customer done (`5843cc8`, `8b8c6d1`, `7707f93`; 349 + 9 tests pass) |
| 7 | This ledger, filled in for A-J | done |
| 8 | Fresh reviewer, fix loop (max 3 rounds) | done: round 1 not clean (2 high, 2 medium, 3 low), all fixed; round 2 **clean** (3 low: two doc gaps fixed in CONTRACTS/OWNERSHIP, gift card cancel order fixed in `668d098`: Stripe refund first, then the card once) |
| 8b | Brand guardian builder (`docs/design/INVENTORY.md`, `DESIGN.md`, brand ADR, `packages/brand`, brand lint, one pilot per app) | done on `build/run-0-brand`: customer-front-end `d0a3736` (packages/brand, 82 tests, brand-lint), admin `fac91b1`, console `1b2ac11`, booqy-website `aa5a7fb`, infrastructure `cdd694a` (INVENTORY.md, DESIGN.md, ADR-BRAND-sharing.md). To review: hand-edited console lockfile; Kontakt button pilot now restaurant-coloured (15 px font, was 17 px); package publishes as `@bookingsystemadvancedorg/brand` aliased to `@booqy/brand` |
| 9 | Commit, merge `build/run-0-brand` into `build/run-0-foundations`, open PRs | done: brand merged in infrastructure, admin, customer, console, booqy-website (no conflicts); all gates green on the merged branches; branches pushed, PRs opened (see below) |

`docs/build/PROMPTS.md` was saved unchanged (byte-identical to the owner's
`booqy-multi-agent-build-prompts_1.md`).

### Decisions taken before Run 0

- The top folder `booqy/` is not a git repo; it holds separate repos. Shared
  build docs (`docs/build`, `docs/adr`, `docs/design`) live in the
  **infrastructure** repo. `packages/brand` will live in
  **customer-front-end/packages/brand**, next to `packages/site-kit`,
  published to GitHub Packages the same way. Code changes go on a
  `build/run-0-foundations` branch in each repo they touch, one PR per repo.
- Run 0 is built in separate git worktrees cut from each repo's `dev`, so the
  owner's working copies on `dev` are never touched.
- The skills `booqy-meta-ads` and `booqy-site-builder` named in PROMPTS.md are
  not installed; the ADRs for A and B will be written from the plan and the
  codebase alone.

### Worktrees and branches

All branches are **local only** (none pushed to origin). Created 2026-11-01
from each repo's `dev` at the commit shown.

Foundations worktrees, branch `build/run-0-foundations`, under
`/Users/akoura/projects/it-hjalparna/booqy-run0/`:

| Repo | Worktree path | Branch | Base commit |
|---|---|---|---|
| infrastructure | `booqy-run0/infrastructure` | `build/run-0-foundations` | `2ca6bca` |
| application | `booqy-run0/application` | `build/run-0-foundations` | `2edc10a` |
| admin-front-end | `booqy-run0/admin-front-end` | `build/run-0-foundations` | `c48d8e1` |
| customer-front-end | `booqy-run0/customer-front-end` | `build/run-0-foundations` | `74cacc5` |
| booqy-console | `booqy-run0/booqy-console` | `build/run-0-foundations` | `e6dfb1e` |
| booqy-website | `booqy-run0/booqy-website` | `build/run-0-foundations` | `1261396` |

Brand guardian worktrees, branch `build/run-0-brand`, under
`/Users/akoura/projects/it-hjalparna/booqy-run0-brand/`:

| Repo | Worktree path | Branch | Base commit |
|---|---|---|---|
| infrastructure | `booqy-run0-brand/infrastructure` | `build/run-0-brand` | `2ca6bca` |
| application | `booqy-run0-brand/application` | `build/run-0-brand` | `2edc10a` |
| admin-front-end | `booqy-run0-brand/admin-front-end` | `build/run-0-brand` | `c48d8e1` |
| customer-front-end | `booqy-run0-brand/customer-front-end` | `build/run-0-brand` | `74cacc5` |
| booqy-console | `booqy-run0-brand/booqy-console` | `build/run-0-brand` | `e6dfb1e` |
| booqy-website | `booqy-run0-brand/booqy-website` | `build/run-0-brand` | `1261396` |

`aws-accounts` has no Run 0 branch or worktree.

### Notes on the worktrees

- **Rebased onto current dev (2026-11-01).** All 12 worktrees now sit on
  their repo's local `dev` (admin-front-end `ab0a8b3`, booqy-console
  `5879a13`, customer-front-end `e36e9d0`, the rest unchanged). Those three
  `dev` commits are not pushed to origin yet, so PRs opened against
  `origin/dev` will show them too until the owner pushes `dev`.
- **Dependency links.** To run builds and tests without reinstalling, each
  worktree links to the main checkout's dependencies: `node_modules` in
  admin-front-end, booqy-console/web, customer-front-end and
  customer-front-end/packages/site-kit, and `.venv` in application. These
  links are excluded locally in each repo's `.git/info/exclude` (never
  committed). booqy-console/api has no local venv.
- **Uncommitted files in the foundations worktree:**
  `infrastructure/docs/build/PROMPTS.md`, `RULES.md`, `EXPLORE-NOTES.md` and
  this file. Nothing is committed on any Run 0 branch yet.
- **Removing them later:** `git -C <main repo> worktree remove <path>` then
  `git -C <main repo> branch -D <branch>`, per repo.

## Contract notes from phase 1

- CONTRACTS.md 1.2 detail-type pattern rejected `Waitlist.Left`,
  `GiftCard.Sold`, `ReviewRequest.Sent`; the generator allows them (lookahead
  capital, `Sent`/`Sold` as irregular past tenses), comment in the generator.
- Swedish labels and English labels of the six existing features were chosen
  by the builder (in `booqy.yaml`); `consoleForwardOps` section added.
- Generated TypeScript is checked by each frontend's typecheck in phase 2.
- Customer: `SiteConfig.tenant.features` is `Record<string, boolean> &
  Partial<Record<SiteFeatureKey, boolean>>` (additive; the exact record broke
  existing fixtures and would narrow a published type). CONTRACTS.md 10
  setBy changed to "Webbplatsen" with `where`, matching existing entries.
  The two new storage entries show on `/cookies` for every restaurant.
- Console decisions accepted by the orchestrator (contract gaps): platform-
  wide audit rows (A15, no tenantId) go under `TENANT#PLATFORM`; A16's
  combined action string is split by the request's `paused`; a forward to an
  undeployed feature Lambda returns 404 `not_found`, a function error or bad
  answer 503 `feature_unavailable`; console feature errors keep the console's
  existing shape (`error` + `fields`). Console web tests need the placeholder
  Cognito values from `web/.env.example` (true before Run 0 too).
- Admin decisions accepted: `statistik.signals` is imported directly (not a
  component slot); the `marketing.mottagare.segments` slot sits just above
  `SubscribersTab` in `MarknadsforingPage`; gift card accounts are optional
  in `Accounts` so older backends still work.
- Application phase 2 notes: AP12 finalising a bill with a gift card answers
  501 `gift_card_receipt_not_supported` because `control_system.py` has no
  voucher payment means (legal check; **blocks feature E**). Stripe
  `charge.dispute.closed` lacks the payment's `metadata.kind`, so gift card
  disputes are not routed (E must handle). `stripe.event` reads
  `metadata.tenantId` (E must set it and check `account`). Online orders
  part-paid by gift card are not split in the accounting export (E). The guest
  status page cannot confirm a part-gift-card order (webhook still does).
  New error code `gift_card_min_order` (under 3 kr left for the card).
  CONTRACTS.md insights path corrected to `GET /insights?locationId=`.
  Open for C/E in Run 1: erase reaching data after a feature is turned off.
- Worktree setup: symlinked root `node_modules` made `@booqy/site-kit`
  resolve to the owner's checkout; the customer worktree now has a local,
  git-excluded `node_modules` of per-package links. Reviewers need the same.

## Review round 1 findings and actions

| # | Sev | Finding | Action |
|---|---|---|---|
| 1 | high | Gift card amounts ignored in order self-heal, staff cancel/refund, fully covered cancel | application builder: charged amount in `session_matches`, `checkout.giftcard op: refund`, skip Stripe refund when nothing charged |
| 2 | high | Hooks gated on "on now" lose erase/export/SIE/gift card events after a feature is turned off | contract: "on or ever on" (`entitlements.featuresEver`, stamped by the console); application + console builders |
| 3 | medium | Brand branch edits files outside its ownership | OWNERSHIP.md: brand guardian Run 0 pilot files listed (done) |
| 4 | medium | Segment campaign stuck "sending" when guestCrm off | application builder: pause with reason |
| 5 | low | Duplicate feature route keys merged silently | infrastructure builder: precondition |
| 6 | low | CONTRACTS 12.3 operator scope text out of date | fixed in CONTRACTS.md (no scope, separate route resource) |
| 7 | low | tenant.purge invokes 10 targets per purged tenant | accepted (contract allows; nothing deployed until Runs 1-3) |

## Run 0 pull requests (against `dev`, all merged 2026-11-01/02)

Merge in this order (RELEASES.md):

1. infrastructure: https://github.com/BookingSystemAdvancedOrg/infrastructure/pull/36 (IAM change and 14 ECR repos need the owner's approval)
2. application: https://github.com/BookingSystemAdvancedOrg/application/pull/68
3. admin-front-end: https://github.com/BookingSystemAdvancedOrg/admin-front-end/pull/21
4. booqy-console: https://github.com/BookingSystemAdvancedOrg/booqy-console/pull/11
5. customer-front-end: https://github.com/BookingSystemAdvancedOrg/customer-front-end/pull/13
6. booqy-website: https://github.com/BookingSystemAdvancedOrg/booqy-website/pull/11

The local `dev` of admin-front-end, booqy-console and customer-front-end has
one unpushed owner commit each; until `dev` is pushed those PRs also show it.

## Final gates on merged `build/run-0-foundations`

| Gate | Result |
|---|---|
| application pytest | 3745 passed, 1 skipped (existing fiskaly live test) |
| gen_contracts --check (5 targets) | in sync |
| terraform fmt / validate | clean / "Success! The configuration is valid." |
| admin lint, tsc, test, build | 0 errors, ok, 657 passed, built |
| console web typecheck, test, build (placeholder env from .env.example) | ok, 103 passed, built |
| console api pytest | 176 passed |
| customer lint, site-kit typecheck, test, build | ok, ok, site-kit + app tests passed, built |
| brand package test, typecheck, build; brand-lint report-only | 82 passed, ok, built; exit 0 |

Not verified here: Terraform plan (CI only), Safari audio and VoiceOver on
the pilots, real Meta/Google/Fortnox/Visma/Bedrock (simulators only).

## Owner approvals needed before Run 0 merges

- **IAM change (IN7, commit `c0a7723`):** one inline policy `feature-hooks`
  per role allowing only `lambda:InvokeFunction` on
  `function:<prefix><target>:live`. Roles and targets: guest-privacy
  (guest-crm, google-business, gift-cards, waitlist); tenant-purge (all ten);
  stripe-webhook, payment-intent, webhook-payment-intent, manage-order
  (added in review round 1, commit `ea51214`), kassa, accounting
  (gift-cards); insights (dish-margin); marketing, marketing-send
  (guest-crm); platform-tenants (meta-ads, site-builder, google-business,
  personalliggare). No OIDC/deploy role or permissions boundary touched.
  Called out per CLAUDE.md; owner approves in the PR.
- **14 ECR repositories (IN5)** are created when the infrastructure PR is
  merged and CI applies it (empty, no Lambdas until Runs 1-3): meta-ads,
  meta-ads-jobs, site-builder, site-builder-render, guest-crm,
  guest-crm-sync, google-business, google-business-jobs, gift-cards,
  waitlist, social-posting, personalliggare, accounting-sync, dish-margin
  (`dev-` prefix in dev). Also new on apply: the `booqy-events` bus.
- **Contract deviations from infrastructure:** operator feature routes carry
  no `platform/admin` scope (matches existing console routes, whose tokens
  lack it; CONTRACTS.md 12.3 said otherwise); operator routes are a separate
  route resource to avoid a dependency cycle.
- **Do not turn the ten new feature keys on for a paying restaurant** before
  that feature's run is merged. The console already offers them as
  checkboxes; switched on today they only show placeholder pages ("Den här
  delen är på väg") in admin and on the guest site, and a gift card code at
  checkout answers 503 `gift_card_unavailable`.

## Independent review (round 3) and fixes

A fresh reviewer re-ran every gate and read the six PRs against RULES.md,
CONTRACTS.md, OWNERSHIP.md and the ADRs. Verdicts: infrastructure and
website merge as they were; application, admin, console and customer merge
after these fixes, all applied on the Run 0 branches:

1. `stripe.event`: the contract (CONTRACTS.md 9.2, ADR-E point 2,
   `booqy.yaml`) now requires gift-cards to ignore an event whose `account`
   is not the card's own `stripeAccountId`; the webhook forwards any
   connected account's `metadata.tenantId`.
2. Brand lint is blocking for feature folders: `brand-lint.config.json` in
   admin, console/web and customer-front-end, `npm run brand-lint` in each
   (DESIGN.md 7, RULES.md gates).
3. Kassa refuses a gift card payment up front (501
   `gift_card_receipt_not_supported`) while the control system port has no
   voucher payment means (`ControlSystem.VOUCHER_METHOD`), so no card is
   debited on a bill that cannot be closed.
4. RULES.md gate: the reviewer runs `gen_contracts.py --check` with the
   sibling worktrees present.
5. The note above about not turning the ten keys on.

## Run 0 addendum (features K and L)

Branch `build/run-0-addendum-kl` (infrastructure, from `origin/dev`),
docs part done 2026-11-02: `docs/adr/ADR-K-events-tickets.md`,
`docs/adr/ADR-L-phone-agent.md`, CONTRACTS.md addendum rows and section
17 (exact `booqy.yaml` additions), OWNERSHIP.md sections K, L and 6
(25 scaffolding tasks), this ledger.

Scaffolding done 2026-11-02 on `build/run-0-addendum-kl` in every repo
(not yet reviewed, not merged):

- application AK1-AK7 (contract, three client ports with simulators,
  tenant and site-config tests, stripe-webhook `kind: ticket` routing,
  OpenAPI fragment expectations).
- infrastructure IK1-IK6 (client variables, plan validation and rows,
  two zero-resource modules with empty route lists, four ECR modules,
  hook-caller IAM rows 11-16). **IAM rows 11-16 need owner approval**
  (CONTRACTS.md 14) before `terraform apply`.
- brand BRK1 (`packages/brand`, merged from `build/run-0-addendum-kl-brand`):
  `Bar variant="live"`, `Chip`, `Card surface="ticket"`, contrast tests,
  DESIGN.md and INVENTORY.md rows. **Open item:** the transcript list
  style for the phone agent (ADR-L admin "Bokad via telefon" transcript)
  is NOT built; it is a Run 2 brand task.
- admin-front-end ADK1-ADK5 (Telefon and Evenemang hidden while off,
  placeholder pages, three slots, guide steps, event scan storage entry).
- booqy-console COK1-COK3 (regenerated contracts, `phone_agent` feature
  module, Integrations tab with `phoneAgent`, slots
  `tenant.integrations.phoneAgent` and `settings.phoneAgent`, generic
  `LIMITS` inputs).
- customer-front-end CUK1-CUK3 (guest events routes and nav link gated on
  `events`, `TICKET_PURCHASE_KEY` and registry entry).

Contract/doc fix pass 2026-11-02 (docs/adr/DECISIONS.md): slot
`settings.phoneAgent` is `feature: null` like `settings.metaAds`;
`insights.events` gate is `ever_on` (staff see the slot, money removed),
CONTRACTS.md 17 now agrees with 8.2 and 9.2; brand-lint blocking globs
cover `features/phone-agent/**`, `features/events-tickets/**` (admin) and
`features/evenemang/**` (customer).

Still open: the fresh review of all five repos' addendum commits.
Open owner decisions are marked **[NEEDS YOUR OK]** in the ADRs and
CONTRACTS.md: plans and prices for both features, included minutes,
retention periods, provider contracts (ElevenLabs, 46elks), art. 50 and
recording wording, VAT treatment of tickets, Kassa ticket payments (v1.1),
entitlement key spelled `phoneAgent` (camelCase, not `phone_agent`).


## Run 1: Wave A (A Meta ads, B1 Site builder core, C Guest CRM)

**State: built, integrated, gates green, NOT reviewed (2026-11-03).** The
worker-orchestrator session had no sub-agent tool, so the builder work was
done in one Opus 5.5 session and **no fresh Fable code reviewer or brand
guardian reviewer has run yet**. Per RULES.md no feature is "verified"
until both sign off; the Booqy Orchestrator runs those reviews on the draft
PRs. Nothing merged.

Branches (pushed): `build/run-1-guest-crm`, `build/run-1-meta-ads`,
`build/run-1-site-builder` per touched repo, merged in that order into
`build/run-1-integration` (no conflicts). Draft PRs from
`build/run-1-integration` into `dev`: see the PR list in the run report.

| Repo | C guest-crm | A meta-ads | B site-builder |
|---|---|---|---|
| application | API C1-C11, sync, hooks (privacy, purge, marketing.segment), rebuild job | API A1-A13, platform hook A14-A17, purge, jobs (workflow tasks, insights, sweep) | API B1-B8, Validate/Promote/MarkFailed, schema v1.json, gen_site_schema.py |
| infrastructure | module, routes, root file | module, ASL, schedules, routes | module, ASL, routes |
| admin-front-end | Gäster, profile, segments, audience picker, badge | Annonser tab, wizard, overview tiles | Webbplats editor |
| booqy-console | none | A14-A17 routes, settings card, tenant section | none (B11-B13 are B2) |
| customer-front-end | none | none | SitePage, BuilderPage, PreviewPage, render-lambda |

Gates on `build/run-1-integration` (2026-11-03):

| Gate | Result |
|---|---|
| application pytest | 3955 passed, 3 skipped (baseline 3834 + 121 new) |
| two-tenant isolation tests (A, B, C) | 3 passed |
| gen_contracts.py --check (siblings beside) | in sync |
| gen_site_schema.py --check | in sync |
| ruff E/F/W on new Python (not a CI gate) | clean |
| terraform fmt -check -recursive | clean |
| terraform validate | each new module validated in isolation with hashicorp/aws 6.20.0 ("valid"); full root not run (registry blocked, Stripe provider unreachable); CI plan pending |
| admin lint / tsc / test / build / brand-lint | 0 errors / ok / see run report / built / no blocking findings |
| console api pytest; web tsc / test / build / brand-lint | 196 passed; ok / 116 passed / built / no blocking findings |
| customer site-kit + app tests, typecheck, build, brand-lint; render-lambda node tests | 106 + 360 + 12 passed; ok; built; no blocking findings; 4 passed |

Not verified (needs real AWS/Meta or a person): Terraform plan/apply, the
Step Functions definitions at runtime, real Meta Marketing API (only the
simulator; `meta_graph_real.py` is still the skeleton), real Bedrock,
stream throttling with a third/fourth reader, the render image build
(no pipeline job yet), UI screenshots light/dark mobile/desktop, keyboard
and contrast audit (brand guardian's job).

Open findings and decisions for the orchestrator:

1. **Live site-kit preview in the admin editor** (ADR-B UI) needs site-kit
   as an admin dependency (shared `package.json`) or a CSP `frame-src`
   change; built instead: structure preview + "Förhandsgranska" opens the
   real render through the private link.
2. **customer `src/App.tsx`** (shared): in builder mode `/` still routes to
   MenyPage; the index route must go to BuilderPage when
   `tenant.site.mode === 'builder'` and `version > 0`.
3. **Stream readers**: guest-crm-sync adds a third reader on the
   reservation and catering-requests streams and a fourth on the order
   stream. An EventBridge Pipe (ADR-C open question 1) is also a reader, so
   it does not help; options: fan out from one consumer, or Kinesis for
   DynamoDB.
4. **Contract notes**: notification kind `meta-ads.cap-warning` (not in
   CONTRACTS 9.4); 409 `assets_missing` also covers "location has no stored
   geocode" (`cateringOrigin.position`); A9 returns no cursor; ADR-B test
   "contrast 3:1 -> 400" cannot happen with the ADR's own nudge rule;
   `VERSION#` gets `publishedAt/publishedBy` stamped once when first live.
5. **Render image pipeline** for `site-builder-render` (ADR-B open
   question 1, owner's `.github`).
5a. **Operator rule (review F11)**: do not switch a tenant to builder mode
   while its site repo workflow still deploys to the root `sites/<t>/`; the
   repo deploy and Promote overwrite each other. Disable or repoint the
   repo's deploy workflow first (`site-builder/README.md`).
6. **`jsonschema`** is pinned in `functions/site-builder/requirements.txt`;
   the test suite gets it via `openapi-spec-validator` (listing it in
   requirements-dev.txt is a shared change).

Accepted debt for Run 1, scheduled for Run 2 (scale; review fix round 2,
not coded on purpose):

7. **Nightly Meta ads statistics run one restaurant after another in one
   job.** Each night at 04:00 a single 5-minute job fetches yesterday's ad
   numbers from Meta for every connected restaurant in turn. With a few
   restaurants this takes seconds; at roughly 100+ connected restaurants
   (or a slow Meta day) it can run out of time, and the restaurants late in
   the list then get no numbers that night (and their spend cap is checked
   a day late). Nothing is double-counted, and the next night's run fills
   the gap only for its own day. Run 2: split the job so each restaurant
   (or small batch) runs on its own, e.g. a Step Functions Map or one
   queue message per restaurant, and alarm when a night is incomplete.
   Owner: meta-ads (application `functions/meta-ads-jobs`, infrastructure
   `meta-ads/`).
8. **Counting a guest segment reads the whole guest list each time.** When
   an owner previews how many guests a segment reaches (Gäster >
   Målgrupper, and the campaign audience picker), the server reads every
   guest profile of the restaurant to count. That is fine for hundreds or
   a few thousand guests, but cost and waiting time grow with every guest
   and with every click. Run 2: cache the count per segment version for a
   short time, or keep running counts, and cap how often a preview can be
   asked for. Owner: guest-crm (application `shared/features/guest_crm`).

IAM (all on NEW roles; no existing role, boundary, OIDC role, Cognito,
CloudFront or KMS changed): see each module README. Call-outs: site-builder
`s3:Get/Put/DeleteObject` on `sites/*` + ListBucket prefix `sites/*`, and
tenant-table UpdateItem limited to attribute `site`; meta-ads Secrets
Manager create/put/get/delete on `booqy/<env>/meta-ads/*`, tenant-table
Get/Put limited to `PLATFORM#META_ADS`, `cloudwatch:PutMetricData`
(namespace-conditioned), Bedrock only when a model id is set; meta-ads-jobs
also gets `states:StartExecution` on the publish state machine (fix round 2:
the 15-minute sweep restarts publishes whose start was lost). New stateful
resources: tables `<prefix>meta-ads`, `<prefix>site-builder`,
`<prefix>guest-crm` (PITR, deletion protection in prod), SQS
`<prefix>guest-crm-sync-dlq`, secret `${prefix}meta-ads/app`, two Standard
state machines.


## Run 2 batch 1 (D Google Business Profile, E Gift cards, F Waitlist, G Social posting)

**State: built, integrated, gates green, NOT reviewed (2026-11-04).** The
worker-orchestrator session had no sub-agent tool, so the four features were
built sequentially (D, F, G, E) in one Opus 5.5 session; **no fresh code
reviewer or brand guardian reviewer has run yet** and no Playwright
screenshots were taken. Per RULES.md none of D, E, F, G is "verified".
Nothing merged. All four entitlements stay `false` in every plan.

Branches (pushed): `build/run-2-google-business`, `build/run-2-waitlist`,
`build/run-2-social-posting`, `build/run-2-gift-cards` per touched repo,
merged in that order into `build/run-2-integration` (cut from `dev`, no
conflicts). Draft PRs from `build/run-2-integration` into `dev` in
infrastructure, application, admin-front-end, booqy-console and
customer-front-end: infrastructure#42, application#73, admin-front-end#26,
booqy-console#16, customer-front-end#18.

| Repo | D google-business | F waitlist | G social-posting | E gift-cards |
|---|---|---|---|---|
| application | API D1-D10, hook D11, purge, privacy hooks; jobs (hourly sync, GuestVisit.Recorded -> schedule, review sender) | API F1-F10, offer timer, hooks | API G1-G8, publish worker, disconnect consumer, purge | API E1-E13, stripe.event, checkout.giftcard, kassa.giftcard, accounting.events, privacy, purge, nightly expiry |
| infrastructure | module, routes, root file | module, routes, root file | module, routes, root file | module (+ pepper secret), routes, root file |
| admin-front-end | GoogleProfileCard, OmdomenTab | QueuePanel, WaitlistSettingsCard | InlaggTab, ShareDishAction | PresentkortPage, KassaGiftCardButton |
| booqy-console | D11 forward + Integrations section | none | none | none |
| customer-front-end | none | KoPage, JoinQueueLink | none | PresentkortPage, SaldoPage, GiftCardField |

Gates on `build/run-2-integration` (2026-11-04, this session):

| Gate | Result |
|---|---|
| application pytest (`-n 8`) | 4100 passed, 3 skipped (new: D 35, F 22, G 20, E 21) |
| two-tenant isolation tests (D, E, F, G) | included above, all pass |
| gen_contracts.py --check (siblings beside) | in sync (exit 0) |
| gen_site_schema.py --check | in sync |
| ruff E/F/W on new Python (not a CI gate) | clean |
| terraform fmt -check -recursive | clean |
| terraform validate (whole root, hashicorp/aws 6.69.1, random 3.6.3, archive 2.7.1, lukasaron/stripe 3.4.0 from a local mirror; no backend) | "Success! The configuration is valid" (deprecation warnings for table-level hash_key/range_key, same as the existing modules) |
| admin lint / tsc / vitest / build / brand-lint | 0 errors (42 warnings, dev has 36; the 6 new are `set-state-in-effect`, the pattern the existing pages use) / ok / 705 passed / built / no blocking findings |
| console api pytest; web tsc / vitest / build / brand-lint | 199 passed (D branch, the only console change); ok / 121 passed / built / no blocking findings |
| customer lint, site-kit tsc, tests (brand, site-kit, app), build, brand-lint | 0 errors; ok; 106 + 374 + 13 passed; built; no blocking findings |

Not verified (needs real AWS, providers or a person): Terraform plan/apply
(CI only), Scheduler one-time schedules and bus rules at runtime, real
Google Business Profile API (simulator only; `google_business_real.py` is
still the Run 0 skeleton), real Meta publishing (A's simulator; App Review
for `pages_manage_posts` / `instagram_content_publish`), Stripe test mode
end to end for gift cards (fake Stripe in tests), SMS/email delivery
(notification mocked), UI screenshots light/dark mobile/tablet/desktop,
keyboard and contrast audit (brand guardian), and the fresh code review.

Fix rounds on `build/run-2-integration` (2026-11-04, application 38f1e00
and 55f372e): see the DECISIONS.md entries of 2026-11-04 (E9 refund order,
`charge.refunded` partial flag, code resend on webhook replay, G
`needs_check` by `created_time`, D review SMS retry).

Open findings and decisions for the orchestrator (contract or hotspot):

1. **D click counting**: `stats.clicks30d` is always 0. The ADR's signed
   marketing redirect (`/m/c/{token}` in `marketing-public`, frozen hotspot)
   only knows campaign links; review emails link straight to the Google
   review URL. Needs a hotspot change (a review-link token kind) in a later batch.
2. **D**: review emails are sent without `MARKETING_CONFIGURATION_SET`
   (the marketing module does not output it), so SES bounce/complaint
   events of review emails are not tracked; add an output (marketing module,
   frozen) or accept.
3. **E data model addition (contract, Fable)**: `TXREF#<txId>` rows
   (cardId per transaction id) so `kassa.giftcard` can verify a Kassa
   payment by its `paymentId`; and `JOB/NIGHTLY` (resume point of the
   nightly job). Not in CONTRACTS.md 4.
4. **E10 "Skicka igen" rotates the code**: codes are stored only as
   HMAC + last4 (ADR-E 3), so a resend issues a new code and the old one
   stops working. ADR text says "resend"; confirm (Fable/owner).
5. **E Kassa is blocked** by Run 0's `ControlSystem.voucher_method = None`
   (501 `gift_card_receipt_not_supported`, legal check of the control
   system's voucher payment means). E12 works; the admin button reverses
   the debit when Kassa refuses. Gift cards in Kassa need that decision.
6. **E accounting**: the card part of a refunded online order is booked on
   the OBS account with a warning (the order export only refunds the Stripe
   part); `charge.dispute.closed` lacks `metadata.kind` (Run 0 note), so
   lost disputes are not routed yet. **VAT treatment: needs accountant review.**
7. **G "Föreslå text"** (Bedrock caption, ADR-G 7) has no route in
   CONTRACTS.md 6.G, so it is not built; drafts use the Swedish template.
8. **F card guarantee** on waitlist conversions: none (ADR-F open question 3, owner to confirm).
9. **ROUTES.md**: `generate_routes.py` lists only the `/tenant/...` and
   `/platform/...` feature routes (the `[^\]]*` list regex stops early), the
   same gap as Run 1's meta-ads; the routes themselves are in the
   `*-routes.tf` lists. Generator fix is integrator work.
10. **G `needs_check` needs `created_time` from the Meta port (follow-up
   in A's files, not G's)**: the worker (application 55f372e) adopts a
   Page post only when `created_time >= firstAttemptAt - 120 s`. A's
   simulator (`shared/meta_graph.py` `publish_page_photo`) stamps no
   `created_time` on the posts it records, and `shared/meta_graph_real.py`
   is still the Run 0 skeleton, so today recovery only matches posts the
   tests add by hand. When A builds `RealMetaGraph.recent_page_posts` it
   must request `fields=id,message,permalink_url,created_time` and return
   `created_time` (ISO 8601 with offset), and the simulator should stamp it
   at publish (DECISIONS.md 2026-11-04, ADR-G 6).

IAM (all on NEW roles; no existing role, permissions boundary, OIDC/deploy
role, Cognito, CloudFront or KMS changed; the hook callers' invoke grants on
the four `:live` aliases exist since Run 0): see each module README and the
infrastructure PR. Rows that touch existing resources: waitlist role item
actions on the reservation and slot-occupancy tables (as
create-pending-reservation) and UpdateItem on the location table limited to
attribute `waitlist`; google-business-jobs GetItem on reservation and order
tables, Query on the consent log, GetSecretValue on the marketing link key,
`ses:SendRawEmail` from the no-reply address, invoke on `notification:live`
for the review SMS (no `sns:Publish`; fix round 2026-11-04);
social-posting GetSecretValue on A's `booqy/<env>/meta-ads/*` and GetItem on
A's table (read only); gift-cards GetSecretValue on the platform Stripe key
and the Turnstile secret; waitlist, gift-cards invoke `notification:live`.
New stateful resources: tables `<prefix>google-business`,
`<prefix>waitlist`, `<prefix>social-posting`, `<prefix>gift-cards`; secrets
`${prefix}google-business/app` (value by hand) and
`${prefix}gift-cards/code-pepper` (random); Scheduler groups
`<prefix>google-business`, `<prefix>waitlist`, `<prefix>social-posting`;
SQS DLQs `<prefix>google-business-dlq`, `<prefix>social-posting-dlq`.

## Feature ledger

Status values: todo | building | reviewing | fixing | verified | blocked |
merged.

| Feature | Status | Branch | Attempts | Open issues | Unverified | Human actions needed |
|---|---|---|---|---|---|---|
| A. Meta ads | on dev, awaiting owner go-ahead (merged to dev 2026-11-04; CI dev smoke tests passed in all repos; real Meta/Bedrock/Step Functions runtime unverified) | `build/run-1-meta-ads` -> `build/run-1-integration` | 1 | see Run 1 open findings 4 | real Meta API, Bedrock, Step Functions runtime, screenshots | Meta Business Verification, App Review, Login for Business config, `meta-ads/app` secret value, Bedrock model access |
| A2. Ads on all platforms (ADR-A2 addendum: adapter port, spend confirmation, schedules, guide, daily view; Run 2) / A3 Google Ads, A4 TikTok (Run 3) | spec written 2026-11-04 (draft PR), todo | `claude/spec-infrastructure-l-counter-offers-a-platforms` | 0 | owner choices in ADR-A2 [NEEDS YOUR OK]: money screens (a/b/c), Google account model, TikTok creative, entitlement keys, schedule auto-activate, Snapchat/Pinterest | real Google Ads and TikTok adapters (simulators only until approvals) | Owner: Google manager account, developer token, Explorer/Basic access, brand verification, OAuth app verification; TikTok developer app, app review, data-security check; lawyer: alcohol per platform, recurring-ad rules |
| B. Site builder | on dev, awaiting owner go-ahead (merged to dev 2026-11-04; CI dev smoke tests passed in all repos; real Meta/Bedrock/Step Functions runtime unverified) | `build/run-1-site-builder` -> `build/run-1-integration` | 1 | Run 1 open findings 1, 2, 4, 5 | render image build, Step Functions runtime, screenshots | Owner: render image job in customer-front-end pipeline |
| C. Guest CRM | on dev, awaiting owner go-ahead (merged to dev 2026-11-04; CI dev smoke tests passed in all repos; real Meta/Bedrock/Step Functions runtime unverified) | `build/run-1-guest-crm` -> `build/run-1-integration` | 1 | Run 1 open finding 3 (stream readers) | stream throttling, screenshots | Lawyer: legitimate-interest assessment template; marketing 19 § existing-customer exception |
| D. Google Business Profile + reviews | on dev, awaiting owner go-ahead (merged 2026-11-04: infra#42, application#73, console#16, admin#26, customer#18; simulators/fakes only, no real-provider tests) | `build/run-2-google-business` -> `build/run-2-integration` | 1 | Run 2 batch 1 findings 1, 2 | real GBP API, Scheduler/bus rule runtime, SES/SNS delivery, screenshots | Google Business Profile API access and OAuth verification of `business.manage`; `google-business/app` secret value; lawyer: review request as marketing / soft opt-in |
| E. Gift cards | on dev, awaiting owner go-ahead (merged 2026-11-04: infra#42, application#73, console#16, admin#26, customer#18; simulators/fakes only, no real-provider tests); **VAT treatment needs accountant review** | `build/run-2-gift-cards` -> `build/run-2-integration` | 1 | Run 2 batch 1 findings 3-6 | Stripe test mode end to end, Kassa (blocked: no voucher payment means), code email delivery, screenshots | Accountant: multi-purpose voucher, 2421/3990, breakage; lawyer: validity 24 months, withdrawal right, kassaregister voucher reporting; decision on the control system voucher means |
| F. Waitlist | on dev, awaiting owner go-ahead (merged 2026-11-04: infra#42, application#73, console#16, admin#26, customer#18; simulators/fakes only, no real-provider tests) | `build/run-2-waitlist` -> `build/run-2-integration` | 1 | Run 2 batch 1 finding 8 | SMS delivery, Scheduler runtime, screenshots | Owner: card guarantee on conversions (v1 none) |
| G. Social posting | on dev, awaiting owner go-ahead (merged 2026-11-04: infra#42, application#73, console#16, admin#26, customer#18; simulators/fakes only, no real-provider tests) | `build/run-2-social-posting` -> `build/run-2-integration` | 1 | Run 2 batch 1 findings 7, 10 | real Meta publishing, Instagram daily post limit, Scheduler/bus rule runtime, screenshots | Meta App Review for `pages_manage_posts` and `instagram_content_publish`; lawyer: alcohol posts (alkohollagen 7 kap.) |
| H. Personalliggare | todo | | 0 | | | Legal review |
| I. Fortnox and Visma posting | todo | | 0 | | | Fortnox and Visma developer access |
| J. Margin per dish | todo | | 0 | | | |
| K. Events and tickets (addendum, Run 2) | scaffolding in production, dark (merged to main by owner 2026-11-02; feature code is Run 2) | `build/run-0-addendum-kl` (all repos) | 1 | ADR-K, contracts, scaffolding AK1-7, IK1-6, ADK1-5, COK1-3, CUK1-3 and brand BRK1 (Chip, Card ticket) done, awaiting fresh review; IAM rows 11-16 need owner approval; feature code itself is Run 2 | Wallet pass signing against real Apple/Google accounts | Accountant: VAT rate list and BAS accounts for tickets (needs accountant review); lawyer: receipt by email, withdrawal-right text, resale terms; Apple Developer Pass Type ID and Google Wallet issuer; owner: plan rows, per-ticket fee or none [NEEDS YOUR OK] |
| L. AI phone agent (addendum, Run 2) | scaffolding in production, dark (merged to main by owner 2026-11-02; feature code is Run 2); **counter-offer flow settled 2026-11-04** (ADR-L decision 13, contract and simulator on the `claude/spec-*` draft PRs) | `build/run-0-addendum-kl` (all repos); spec: `claude/spec-application-l-counter-offers`, `claude/spec-infrastructure-l-counter-offers-a-platforms` | 1 | ADR-L, contracts, scaffolding AK1-7, IK1-6, ADK1-5, COK1-3 and brand BRK1 (Bar live, Chip) done, awaiting fresh review; transcript list style not built (open brand item, Run 2); `settings.phoneAgent` fixed to `feature: null` (DECISIONS.md); IAM rows 11-16 need owner approval; 46elks SIP-forward capability to verify in sandbox week 1 of Run 2; Run 2 builder brief: counter-offers per decision 13 (tool-side `offers()`, staff manual route with `source: phone`, `list-layout-version:live` invoke, L4 `counterOffers`), guarantee-size parties get a callback until the manual-route hotspot upgrade | Real voice latency and Swedish quality (Run 3 voice QA); Nova Sonic language list (quarterly); counter-offer tool side (simulator scripts only so far) | Voice provider account, EU residency and DPA (ElevenLabs proposed); SIP provider account, KYC and Swedish numbers (46elks proposed); Bedrock model access for `phone_agent_model_id`; lawyer: art. 50 wording, recording notice and basis, privacy notice paragraph; accountant: VAT on per-location and per-minute lines; owner: plans, included minutes, prices, retention options, default agent name, reserved concurrency, counter-offer choices of decision 13 (three offers, earlier-wins tie, one next day then callback, nearby-table interpretation and 1.0 m gap, nearby before times, toggle defaults, manual-route guarantee upgrade) [NEEDS YOUR OK]; IAM rows 11-16 approval; new IAM row for Run 2: `phone-agent-call` invoke on `list-layout-version:live` |
