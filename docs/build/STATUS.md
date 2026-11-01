# Build status

Ledger for the multi-agent build in `docs/build/PROMPTS.md`. Read this
first when a run starts or resumes; skip anything already verified or merged.

Last updated: 2026-11-01 (Run 0 complete).

## Run 0: Foundations

**State: done. Run 0 complete on 2026-11-01; PRs open against `dev` (not merged). Do not start Run 1 until the owner has merged Run 0.**

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

## Run 0 pull requests (against `dev`, not merged)

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

## Feature ledger

Status values: todo | building | reviewing | fixing | verified | blocked |
merged.

| Feature | Status | Branch | Attempts | Open issues | Unverified | Human actions needed |
|---|---|---|---|---|---|---|
| A. Meta ads | todo | | 0 | | | Meta Business Verification, App Review |
| B. Site builder | todo | | 0 | | | |
| C. Guest CRM | todo | | 0 | | | |
| D. Google Business Profile + reviews | todo | | 0 | | | Google Business Profile API access |
| E. Gift cards | todo | | 0 | | | Accountant: gift card VAT (single- or multi-purpose) |
| F. Waitlist | todo | | 0 | | | |
| G. Social posting | todo | | 0 | | | Depends on A's Meta connection |
| H. Personalliggare | todo | | 0 | | | Legal review |
| I. Fortnox and Visma posting | todo | | 0 | | | Fortnox and Visma developer access |
| J. Margin per dish | todo | | 0 | | | |
