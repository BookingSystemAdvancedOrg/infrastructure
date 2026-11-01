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
- Contracts: the reviewer runs `python scripts/gen_contracts.py --check` in the application
  worktree with the admin, console and customer worktrees checked out beside it. CI only checks
  application's own copy (`tests/test_contracts.py` skips the siblings when they are absent), so
  this is the only place a hand-edited generated file is caught.
- Brand: `npm run brand-lint` exits 0 in every touched frontend (feature folders are blocking).
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
