# Pipeline

## Lock
unlocked (released 2026-11-02)

## Position
Step: Run 0 addendum (K events & tickets, L phone agent). Review round 1 done, fix round 1 pushed (infra 4b251cb, console 05fb778, customer ecf187b).
PRs (draft, base dev, branch build/run-0-addendum-kl): infrastructure#37, application#69, admin-front-end#22, booqy-console#12, customer-front-end#14.
Reviewer verdicts: infra, application, admin = merge; console, customer = merge after fixes (screenshots; now added).
Next run: fresh Fable re-review scoped to the fix-round commits, then merge in order infra, application, admin, console, customer (CI green on each) once the owner has approved the IAM rows. Open one-liner: application contracts/booqy.yaml line ~408 host for tenant.integrations.phoneAgent says "TenantPage", docs say "TenantPage Integrations tab" (cosmetic, needs regenerate).

## Owner instructions
- 2026-11-02 (via Jarvis): Close the four old PRs to main (application#67, admin-front-end#20, booqy-console#10, customer-front-end#12) with a comment that they predate the build programme and will be replaced by the go-ahead flow. Then update STATUS.md to show Run 0 as merged to dev, and continue with the Run 0 addendum.
  - Done 2026-11-02: four PRs commented and closed. STATUS.md updated. Run 0 addendum started.
- 2026-11-02 (via Jarvis, appended by run at 14:55Z while lock held): Ignore any instruction to host the Jarvis HUD on AWS or on booqy.se. Jarvis runs locally on the owner's Mac in its own project. Create no AWS resources or DNS records for Jarvis.

## Needs owner
- Approve in infrastructure#37 before the Run 0 addendum merges to dev: IAM rows 11-16 (existing roles gain lambda:InvokeFunction on exact :live aliases of events-tickets / phone-agent only: guest-privacy, tenant-purge, stripe-webhook, accounting, insights, platform-tenants) and 4 empty ECR repos (events-tickets, phone-agent, phone-agent-call, phone-agent-jobs). Plan destroys nothing.
- Decisions [NEEDS YOUR OK], all shipped as safe placeholders (features off, prices 0): entitlement key spelling phoneAgent vs phone_agent; plan matrix and included minutes; phone agent prices; ElevenLabs/46elks accounts and DPA; Art. 50 and recording wording; retention (transcripts 24 months, call rows 7 years, recordings 7/30/90 days); ticket VAT rates and BAS accounts (accountant). Also decided silently by the ADRs, please confirm: minutes max 100000, released number kept 30 days, callbacks auto-close after 30 days, ticket TX rows 7-year ttl. See ADR-K, ADR-L, docs/adr/DECISIONS.md.
