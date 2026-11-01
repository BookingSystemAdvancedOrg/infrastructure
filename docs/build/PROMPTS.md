# Booqy: multi-agent build prompts

Paste these into Claude Code in the `booqy` project, **one run at a time**. Start each run in a fresh session. Each run ends with a hand-off you review before starting the next.

## Why four runs and not one

- **Shared files.** Every feature touches the same files: `app/shared/tenant.py` (entitlements), `infra/variables.tf` (plans), `console/api/src/app/tenants.py`, `admin/shared/AdminLayout.tsx` (sidebar), the storage registries and `/site-config`. If parallel agents edit these at once, the merges break. Run 0 changes them once, then the feature agents leave them alone.
- **Approvals outside the code.** Meta Business Verification and App Review, Google Business Profile API access, and Skatteverket's personalliggare rules all depend on someone outside the codebase. Features that depend on them are built against mocks first.
- **Review quality.** One huge run fills each agent's context and reviews get shallow. Smaller waves with fresh reviewers catch more.
- **No setup can promise zero mistakes.** These prompts make mistakes **caught, not shipped**: mechanical gates, an independent reviewer per feature, a fix loop with a retry limit, an integration pass and a final audit. Anything that can't be verified is reported as unverified, not passed off as done.

| Run | What | Parallelism |
|---|---|---|
| 0 | Foundations: rules, ADRs, shared contracts, entitlements, file ownership, **shared brand system (tokens, effects, one Bar, one of each component)** | Sequential (1 builder + 1 brand builder + 1 reviewer) |
| 1 | Meta ads · site builder (schema, renderer, publish) · guest CRM | 3 builders in parallel, each gated by the brand guardian |
| 2 | Google Business Profile + reviews · gift cards · waitlist · social posting · personalliggare · builder AI editing + custom-code tier | 5–6 builders in parallel, each gated by the brand guardian |
| 3 | Fortnox/Visma direct posting · margin per dish · **brand consolidation of all existing UI** · integration hardening, end-to-end tests, security audit, docs | 2 builders + consolidation agents, then an audit |

### The brand guardian

The brand guardian is one agent role, used three ways:
1. **Run 0, builder.** It inventories every effect and component across the admin app, the console, the site kit, the restaurant sites and booqy.se, then builds one shared brand package. That package has the tokens, the effects (glass, liquid fill, sidebar pour, count-up, click sound, skeletons, receipt print) and **one `Bar` component family**. "Bar" covers progress, busy and loading bars, chart bars, meters, tab bars, top and nav bars, the submit/action bar, and toasts or banners shown as bars. Every bar uses the same component in every app.
2. **Runs 1–2, gate.** Every feature PR needs the brand guardian's sign-off as well as the code reviewer's. It rejects hand-rolled bars, one-off animations, hard-coded colours, spacing or radii, and new components that duplicate shared ones.
3. **Run 3, consolidation.** It moves all existing UI onto the shared package and deletes the duplicates.

**One rule to keep in mind:** restaurant sites use the **same components and effects** but **the restaurant's colours, logo and fonts**, through theme tokens. Guests should see the restaurant's brand, not Booqy's. Booqy's own look (browns, glass, wine red `#350001`) applies to the admin app, the console and booqy.se.

---

## RUN 0: Foundations (paste first)

```
You are the lead engineer and orchestrator for Booqy (see CLAUDE.md, BUSINESS-REQUIREMENTS.md,
infra/docs/MULTI-TENANCY.md, infra/docs/RELEASES.md). This is Run 0 of 4. Its only job is to lay
foundations so later runs can build features in parallel without conflicts. Do NOT build features.

Skills: engineering:architecture, engineering:system-design, ponytail, ponytail-review,
booqy-meta-ads, booqy-site-builder, engineering:testing-strategy.

Features in scope for the whole programme (Runs 1-3):
 A. Meta login + 2-minute ad wizard + ad insights (skill: booqy-meta-ads)
 B. Site builder: schema-driven Utkast/Publicerad builder with AI edits, plus the per-tenant
    repo kept as a Booqy-staff-maintained custom-code tier with preview/live (skill: booqy-site-builder)
 C. Guest CRM: unified guest profile across bookings/orders/catering, new vs returning, segments
 D. Google Business Profile sync (hours, special days) + post-visit review requests
 E. Gift cards / vouchers (sell on site, redeem online and in Kassa, accounting treatment)
 F. Waitlist / walk-in queue (Bokningar + Layout)
 G. Organic Instagram/Facebook posting of menu changes and specials (reuses A's connection)
 H. Personalliggare (electronic staff ledger) linked to staff users and locations
 I. Direct posting to Fortnox and Visma (extends Bokföring)
 J. Margin per dish (ingredient cost on menu items, shown in Statistik)

Do this, in order:

1. Write docs/build/RULES.md containing the OPERATING RULES block below, verbatim.
2. Read the codebase (use Explore agents in parallel for: app/, infrastructure/, admin-front-end/,
   customer-front-end/ incl. site-kit, booqy-console/). Return conclusions, not file dumps.
3. Write one ADR per feature A-J in docs/adr/ (engineering:architecture). Each ADR: decision,
   data model (DynamoDB tables + keys, tenant in partition key), API routes, events, Terraform
   modules, entitlement name, plan availability, UI placement, external dependencies and which
   are mocked, privacy/GDPR impact (retention, consent, storage registry), Swedish legal notes to
   be checked by a human (gift card VAT single-/multi-purpose, personalliggare, DSA), test plan.
4. Write docs/build/CONTRACTS.md: every new route, table, event (EventBridge detail-type +
   schema), entitlement, plan matrix row, sidebar entry, site-config field and storage-registry
   entry, so feature agents implement against a fixed contract.
5. Write docs/build/OWNERSHIP.md: for each feature, the directories/files it may create or edit.
   Shared hotspots are owned ONLY by the orchestrator/integrator and are changed in this run.
6. Implement the shared scaffolding now, once: new entitlements (default off, per-tenant
   override in console), plan matrix in Terraform, empty sidebar slots behind entitlements,
   empty Terraform module stubs, contract types (Python + TS) generated from one source,
   test fixtures for two tenants (for isolation tests), mock clients for Meta, Google Business
   Profile, Fortnox, Visma (same pattern as the dev simulators for signing/readers).
7. Write docs/build/STATUS.md: a ledger with one row per feature A-J and columns
   status (todo|building|reviewing|fixing|verified|blocked|merged), branch, attempts, open issues,
   unverified items, human actions needed.
8. Verification: spawn a fresh general-purpose agent that has NOT seen your work. Give it only
   the ADRs, contracts, ownership map and the diff. It checks: contracts complete and consistent,
   ownership has no overlaps, every new route has a tenant-isolation test planned, nothing
   breaks existing BR-* requirements, all gates pass. Fix its findings; repeat until clean
   (max 3 rounds, then list remaining issues in STATUS.md).
8b. BRAND SYSTEM. In parallel with steps 3-7, launch a "brand guardian" builder agent
   (isolation: worktree, branch build/run-0-brand; skills: impeccable, design:design-system,
   design:accessibility-review, ponytail). Its brief:
   - Inventory every visual effect and component in admin-front-end, booqy-console/web,
     customer-front-end (incl. site-kit), booqy-website and email templates: colours, type,
     spacing, radii, shadows, glass, motion (liquid fill, sidebar pour, count-up, skeletons,
     receipt/print animation, busy bar), click sound, and EVERY bar-like element (progress/busy/
     loading bars, chart bars, meters/rings, tab bars, top/nav bars, sidebar, submit/action bars,
     banners/toasts shown as bars). Write docs/design/INVENTORY.md listing each variant with file
     paths and which ones are duplicates.
   - Write docs/design/DESIGN.md: tokens, effect catalogue (name, when to use, duration/easing,
     reduced-motion fallback), the component catalogue, and the theming model: Booqy theme for
     admin/console/booqy.se; restaurant theme (restaurant colours/logo, contrast-nudged per
     BR-NFR-034) for guest sites, same components and effects underneath.
   - Write an ADR choosing how the separate repos share it (e.g. private npm package on GitHub
     Packages vs git submodule vs copied build output for the static booqy.se), then build
     packages/brand: tokens (single source -> CSS variables + TS), effects as reusable
     primitives, ONE Bar component family with variants (progress, busy, chart, meter, tab,
     nav, action, banner), plus Button, Card, Modal, Field, Select, Skeleton, Toast, StatTile,
     Chart wrappers. Light+dark, mobile/tablet/desktop, reduced motion, keyboard, 4.5:1.
   - Add a lint rule/check (stylelint + eslint or a script in CI) that fails on: hard-coded
     colours/spacing/radii/durations outside packages/brand, bar-like elements not built from
     the Bar family, keyframes/animations defined outside packages/brand, duplicates of
     catalogue components. Run it in report-only mode on existing code (Run 3 fixes it) and in
     blocking mode for new code paths listed in OWNERSHIP.md.
   - Do NOT migrate existing screens yet (Run 3), except a one-screen pilot per app to prove it.
   The fresh reviewer in step 8 also reviews this branch.
9. Commit to branch build/run-0-foundations (merge build/run-0-brand into it) and open a PR. Stop and summarise: what was decided,
   human actions needed (Meta Business Verification, Google API access, legal checks), and
   anything you were unsure about. Do not start Run 1.

=== OPERATING RULES (copy into docs/build/RULES.md) ===
Safety
- Never push to main or dev, never merge PRs, never run terraform apply, never deploy, never
  touch production accounts, secrets or live Stripe/Meta/Google keys. Plan/validate only.
- Never weaken existing security: tenant comes from the token claim; foreign items return 404;
  secrets in Secrets Manager; least-privilege IAM per Lambda; CSP unchanged unless an ADR says so.
- Never add cookies, pixels or browser storage without updating the storage registry; no Meta Pixel.
Honesty
- Never skip, delete, weaken or mark-as-expected a failing test to get green. Never add
  type-ignore/eslint-disable/noqa to silence a real error. Never fake a mock response to match an
  assertion. If something can't be verified (needs real AWS, Meta review, legal), say so in
  STATUS.md under "unverified".
Scope
- Edit only files your feature owns in docs/build/OWNERSHIP.md. If you need a shared change,
  stop and report it to the orchestrator; don't make it yourself.
- Implement exactly the contract in docs/build/CONTRACTS.md. If the contract is wrong, report it.
- Smallest complete change (ponytail). Swedish UI copy (design:ux-copy), English console.
Quality gates (all must pass before a feature can be "verified")
- Lint, typecheck, unit tests for every touched package; terraform fmt + validate (+ tflint/
  checkov if configured); build of every touched frontend.
- Every new endpoint: happy path, validation error, wrong role, foreign tenant -> 404,
  entitlement off -> refused, idempotent retry.
- Every workflow/scheduled job: idempotent and resumable test.
- UI: light + dark, mobile/tablet/desktop, keyboard, 4.5:1 contrast (design:accessibility-review).
Brand
- All UI uses packages/brand only: tokens, effects and components from docs/design/DESIGN.md.
  No hard-coded colours, spacing, radii, shadows, durations or keyframes in feature code.
- Every bar-like element (progress, busy, chart, meter, tab, nav, action, banner) uses the Bar
  family. If a variant is missing, request it from the brand guardian; never hand-roll one.
- Guest/restaurant sites use restaurant theme tokens; admin, console and booqy.se use the Booqy theme.
- The brand lint check must pass for new code.
- A feature is "verified" only with sign-off from BOTH the code reviewer and the brand
  guardian reviewer (a fresh agent with skills impeccable + design:design-system, given
  DESIGN.md, INVENTORY.md and the diff, plus screenshots of each new screen in light/dark at
  mobile and desktop taken with Playwright).
Process
- Builder agent works in its own git worktree on branch build/<feature>.
- Reviewer agent is fresh, never the builder, and is given only: ADR, contract, ownership,
  diff, RULES.md. It runs the gates itself (never trusts the builder's report), runs
  ponytail-review, and returns findings ranked by severity with file:line.
- Fix loop: findings go back to the SAME builder (SendMessage) to fix; reviewer re-checks.
  Max 3 rounds. After that: status=blocked with the open findings; do not loop forever.
- Update docs/build/STATUS.md after every state change so the run can resume after a crash or
  context loss: on start, read STATUS.md and skip anything already verified/merged.
=== END RULES ===
```

---

## RUN 1: Wave A (after you've merged Run 0)

```
You are the orchestrator for Booqy Run 1 of 4. Read docs/build/RULES.md, CONTRACTS.md,
OWNERSHIP.md, STATUS.md and the ADRs for A, B and C. Follow RULES.md strictly.
Resume from STATUS.md: skip features already verified or merged.

Build in parallel, each by its own builder agent (Agent tool, isolation: "worktree",
general-purpose), all launched in one message:
 A. Meta ads (skill booqy-meta-ads): Meta connect via Facebook Login for Business, per-tenant
    token in Secrets Manager, asset picker with missing-asset deep links, DSA payer/beneficiary,
    ad wizard (goal -> creative from menu photo + Bedrock Swedish copy -> budget -> radius ->
    preview -> PAUSED create -> activate), Step Functions publish workflow, caps + kill switch +
    spend alarm, nightly insights sync into Marknadsföring with cost per booking/order via UTM.
    All Meta calls go through the mock client; the real client sits behind config.
 B. Site builder core (skill booqy-site-builder): versioned JSON site schema, draft + immutable
    versions + published pointer, block editor UI in admin (impeccable), private preview link,
    publish = validate + contrast + pre-render static HTML to S3 + pointer swap, one-click
    rollback, site-kit renders from the published document. No AI editing yet (Run 2).
 C. Guest CRM: unified guest profile keyed per tenant (hashed contact identifiers), new vs
    returning, visit/order/catering history, segments (lapsed N days, birthday, high value,
    opted-in), segment export to marketing campaigns. Respect consent log, retention and erase
    (BR-NFR-008, BR-REST-093): erasing a guest must erase the profile.

Builder brief must include: the ADR, contract, ownership list, RULES.md, the skills to use,
and "report back: files changed, gates run with output summary, unverified items".

For each builder, when it reports done: launch a fresh code reviewer AND a fresh brand guardian
reviewer in parallel (rules as in RULES.md). Merge both finding lists into one fix loop.
Keep at most 3 builders plus their reviewers active at once. If a builder needs a Bar variant or
component that packages/brand lacks, a single brand guardian builder adds it on branch
build/brand-additions (the only agent allowed to edit packages/brand this run); builders wait
for it rather than hand-rolling.

When A, B and C are verified (or blocked): launch an integrator agent that merges the branches
one at a time into build/run-1-integration, resolves conflicts only inside owned files, reruns
ALL gates for the whole repo plus the two-tenant isolation suite, and reports. Then launch a
final fresh auditor running ponytail-audit on the integration branch scoped to the new code;
send its high/critical findings back through the fix loop.

Open one PR from build/run-1-integration. Finish with: what's done, what's blocked and why,
unverified items, human actions. Do not start Run 2.
```

---

## RUN 2: Wave B

```
You are the orchestrator for Booqy Run 2 of 4. Read docs/build/RULES.md, CONTRACTS.md,
OWNERSHIP.md, STATUS.md and ADRs D, E, F, G, H and B. Follow RULES.md strictly.
Resume from STATUS.md.

Parallel builders (worktrees, launched together, max 4 builders active, queue the rest):
 D. Google Business Profile: connect, sync opening hours + special days (one-way, Booqy is the
    source), post-visit review request by email/SMS after arrived bookings and completed orders
    (configurable delay, once per guest per N days, never to non-consenting guests if the ADR
    says marketing consent applies). Mock client until API access is granted.
 E. Gift cards: buy on the restaurant site (Stripe on the connected account), code + email,
    balance, partial redemption online and in Kassa, expiry per Swedish rules from the ADR,
    accounting entries in Bokföring per the ADR's VAT decision. Flag the VAT treatment as
    "needs accountant review" in STATUS.md.
 F. Waitlist: guest joins from site when full, staff queue in Bokningar, SMS when a table frees,
    hold window, conversion to booking with existing double-booking protection.
 G. Social posting: reuse A's Meta connection, post dish/special to FB Page + Instagram,
    scheduled posts, drafts generated from menu items. No new token storage.
 H. Personalliggare: check-in/out per staff and location, immutable append-only ledger,
    corrections as new records with reason, export for inspection per the ADR. Flag as
    "needs legal review" and never label it compliant in UI or marketing copy.
 B2. Builder AI editing + custom-code tier: Bedrock prompt -> schema-validated JSON patch ->
    visual diff -> apply to draft; per-plan monthly quota. Custom-code tier on the existing
    site-<slug> repo: console-only for Booqy staff, PR -> preview prefix in the tenant's own
    S3 folder -> owner sees the same Utkast/Publicerad buttons -> promote to live; permissions
    boundary unchanged.

Same review (code reviewer + brand guardian reviewer) -> fix loop, same single brand guardian
builder for any packages/brand additions -> integrator (build/run-2-integration, merged on top of Run 1)
-> auditor -> PR as in Run 1. Finish with the same summary. Do not start Run 3.
```

---

## RUN 3: Accounting, hardening and release readiness

```
You are the orchestrator for Booqy Run 3 of 4. Read docs/build/RULES.md, CONTRACTS.md,
OWNERSHIP.md, STATUS.md and ADRs I and J. Follow RULES.md strictly. Resume from STATUS.md.

Phase 1, parallel builders:
 I. Fortnox and Visma direct posting of the existing daily verifikationer (OAuth per tenant,
    tokens in Secrets Manager, idempotent posting with per-day keys, retry + DLQ, status in
    Bokföring, SIE export stays as fallback). Mock clients.
 J. Margin per dish: cost per menu item (manual entry), margin in Statistik charts and
    "Att göra" signals, hidden from staff when amounts are hidden (BR-REST-084).
Same review (code reviewer + brand guardian reviewer) -> fix loop.

Phase 1b, brand consolidation (in parallel with I and J; one consolidation agent per app,
each in its own worktree, owning only its app: admin-front-end, booqy-console/web,
customer-front-end incl. site-kit, booqy-website, email templates):
 - Using docs/design/INVENTORY.md, replace every duplicate effect, bar and component with
   packages/brand. Delete the old code; don't leave it unused.
 - Switch the brand lint check to blocking for the whole app; it must pass.
 - Before/after Playwright screenshots of every route in light/dark at mobile and desktop;
   a fresh brand guardian reviewer compares them. Intended changes = consistency only; flag any
   layout, behaviour or copy change as a bug. Existing tests must still pass unchanged.
 - Keep the guest sites on restaurant theming; verify with two test tenants that have very
   different colours.

Phase 2, hardening (after I and J are verified), parallel agents:
 - End-to-end tests (Playwright) for the main flows of every feature A-J, light+dark, mobile.
 - Security reviewer: tenant isolation on all new routes, IAM least privilege, secrets
   handling, webhook signature checks, CSP, injection; uses engineering:code-review.
 - Accessibility + copy reviewer: design:accessibility-review and design:ux-copy on new UI.
 - Cost reviewer: Bedrock, Meta/Google API call volumes, DynamoDB access patterns, Lambda
   memory; flag anything that scales per tenant badly.
Findings go through the fix loop with owners of the files.

Phase 3: integrator merges into build/run-3-integration and runs all gates. A fresh auditor
runs ponytail-audit on the whole repo. Then:
 - Update BUSINESS-REQUIREMENTS.md with new BR-* entries (same style, evidence paths).
 - Write docs/build/RELEASE-CHECKLIST.md (engineering:deploy-checklist): order of rollout per
   RELEASES.md, entitlements to enable per tenant, external approvals still pending, legal
   reviews pending, rollback steps.
Open the PR and finish with: done, blocked, unverified, human actions before production.
```

---

## Notes for you

- **Start the outside approvals today.** Meta Business Verification and App Review, Google Business Profile API access, an accountant for gift card VAT, and legal review for personalliggare take longer than the code.
- **Merge each run's PR yourself** after reading the summary. The prompts never merge, apply Terraform or deploy.
- **If a run dies midway,** paste the same prompt again. It reads `STATUS.md` and resumes.
- **Use a strong model for the orchestrator and reviewers.** Reviewers matter more than builders.
