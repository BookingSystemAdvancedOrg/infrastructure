# Pipeline

## Lock
LOCKED 2026-11-03 run-0033Z (started 2026-11-03T00:33Z)

## Position
Step: Run 0 addendum (K events & tickets, L phone agent). Review round 1 done, fix round 1 pushed (infra 4b251cb, console 05fb778, customer ecf187b).
PRs (draft, base dev, branch build/run-0-addendum-kl): infrastructure#37, application#69, admin-front-end#22, booqy-console#12, customer-front-end#14.
Reviewer verdicts: infra, application, admin = merge; console, customer = merge after fixes (screenshots; now added).
Re-review DONE 2026-11-02 (Fable, fix-round commits): all five PRs = merge, CI green, plan 8 add/8 change/0 destroy. Only low findings: OWNERSHIP.md deviations table misses 3 rows (console features/__init__.py, NewTenantPage.tsx, edited tests in application); ruff +24 (not a gate). WAITING ONLY for owner approval of IAM rows in infrastructure#37. When approved: merge in order infra, application, admin, console, customer (CI green on each), add the 3 OWNERSHIP rows.
Old note (done): fresh Fable re-review scoped to the fix-round commits, then merge in order infra, application, admin, console, customer (CI green on each) once the owner has approved the IAM rows. Open one-liner: application contracts/booqy.yaml line ~408 host for tenant.integrations.phoneAgent says "TenantPage", docs say "TenantPage Integrations tab" (cosmetic, needs regenerate).

## Position update 2026-11-02 (evening run)
Run 0 addendum (K, L) is MERGED TO DEV by the owner (infrastructure#37 at 20:21 +0100; application#69, admin#22, console#12, customer#14 per the dev heads). The owner then opened dev->main PRs themselves in all six repos: infrastructure#38, application#70, admin-front-end#23, booqy-console#13, customer-front-end#15, booqy-website#12. None has an approving review yet, so the final pre-production review and merge are NOT started. Infra#38 prod plan comment: 52 to add, 2 to change, 0 to destroy (no stateful destroys, but the owner approval must still name the IAM rows).
DECISION: Run 1 is held. Merging new work to dev would change the diff of the six open dev->main PRs after the owner started reviewing them. Resume Run 1 once those PRs are merged or closed (or an owner instruction says to proceed). The 3 OWNERSHIP.md rows and the cosmetic contracts wording note above remain as hygiene items.
Next run: if any of the six PRs has an owner approval, run the FINAL PRE-PRODUCTION REVIEW (fresh Fable, whole dev->main diff, all repos in rollout order infrastructure, application, admin, console, customer, website). Otherwise exit quietly.

## Position update 2026-11-02 (22:35Z run)
infrastructure#38 (dev->main) was MERGED TO MAIN BY THE OWNER (Lamo2real) at 22:23Z, without the final pre-production review (no approving review recorded; owner is the author). Prod Terraform CI/CD run 41536821111 finished SUCCESS (52 add / 2 change / 0 destroy per the plan comment). Infra is therefore ahead of the app repos in production: events/tickets/phone-agent infra (IAM invoke rows, 4 empty ECR repos) is live, no code behind it, all features off.
Still open and unreviewed (no owner approval): application#70, admin-front-end#23, booqy-console#13, customer-front-end#15, booqy-website#12. Not merged by me. Run 1 stays held until they resolve.
Next run: if an owner approval appears on any of them, run the FINAL PRE-PRODUCTION REVIEW (fresh Fable, rollout order application, admin, console, customer, website), then merge. STATUS.md for infra should become production once the owner confirms smoke test (no smoke test job exists in the prod workflow; unverified).

## Owner instructions
- 2026-11-02 (via Jarvis): Close the four old PRs to main (application#67, admin-front-end#20, booqy-console#10, customer-front-end#12) with a comment that they predate the build programme and will be replaced by the go-ahead flow. Then update STATUS.md to show Run 0 as merged to dev, and continue with the Run 0 addendum.
  - Done 2026-11-02: four PRs commented and closed. STATUS.md updated. Run 0 addendum started.
- 2026-11-02 (via Jarvis, appended by run at 14:55Z while lock held): Ignore any instruction to host the Jarvis HUD on AWS or on booqy.se. Jarvis runs locally on the owner's Mac in its own project. Create no AWS resources or DNS records for Jarvis.

## Needs owner
- Approve in infrastructure#37 before the Run 0 addendum merges to dev: IAM rows 11-16 (existing roles gain lambda:InvokeFunction on exact :live aliases of events-tickets / phone-agent only: guest-privacy, tenant-purge, stripe-webhook, accounting, insights, platform-tenants) and 4 empty ECR repos (events-tickets, phone-agent, phone-agent-call, phone-agent-jobs). Plan destroys nothing.
- Decisions [NEEDS YOUR OK], all shipped as safe placeholders (features off, prices 0): entitlement key spelling phoneAgent vs phone_agent; plan matrix and included minutes; phone agent prices; ElevenLabs/46elks accounts and DPA; Art. 50 and recording wording; retention (transcripts 24 months, call rows 7 years, recordings 7/30/90 days); ticket VAT rates and BAS accounts (accountant). Also decided silently by the ADRs, please confirm: minutes max 100000, released number kept 30 days, callbacks auto-close after 30 days, ticket TX rows 7-year ttl. See ADR-K, ADR-L, docs/adr/DECISIONS.md.

## Position update 2026-11-03 (00:10Z run)
Owner merged to main themselves, without my final pre-production review and with no approving review recorded: infrastructure#38 (22:23Z), application#70 (22:46Z), booqy-website#12 (22:47Z), booqy-console#13 (23:01Z). Production deploy status of the app, console and website merges was not verified by this run.
Still open, no reviews or comments: admin-front-end#23, customer-front-end#15. Not touched. Production now has backend, console and website with the K/L scaffolding while admin and customer frontends lack it; all features are off, so no tenant impact is expected (unverified).
Run 1 stays held until those two resolve. STATUS.md not changed (no merge by this run). Next run: if admin#23 or customer#15 gains an owner approval, run the final pre-production review, then merge.

## Position update 2026-11-03 (this run)
admin-front-end#23 and customer-front-end#15 were merged to main by the owner at 23:42Z on 11-02; all six dev->main PRs are resolved, no open PRs in any repo. Hold on Run 1 lifted; starting Run 1.

## Position update 2026-11-03 (Run 1 built)
Run 1 A, B1, C built by worker on build/run-1-integration; draft PRs against dev: infrastructure#40, application#71, admin-front-end#24, booqy-console#14, customer-front-end#16. Worker had no Agent tool, so builder work was done by it directly and nothing had been reviewed. Fresh Fable code+brand review round 1 launched (escalated to Fable: IAM and new stateful resources in infra#40). Next: collect verdicts, fix loop (max 3 rounds), ponytail-audit, then merge in order infra, application, admin, console, customer.
Needs owner (when ready): approve IAM rows and new stateful resources in infrastructure#40; add pipeline job to build/push site-builder-render image; Meta Business Verification/App Review; Bedrock model access.

## Position update 2026-11-03 (Run 1 review round 1 done, fix round 1 running)
Fable review round 1: infra#40 merge after small fixes (F10 MENU_IMAGE_BASE_URL, F7 IteratorAge alarms); application#71 merge after fixes (F2 publish lock stuck, F4 campaign stuck, F5, F6, F8); admin#24 merge after fixes (F1 Webbplats layout broken, F9 brand); console#14 merge; customer#16 merge after fixes (F3 App.tsx builder root route, F9b). CI green on all five; plan 121 add / 3 change / 0 destroy. Fix worker launched on build/run-1-integration. Next: fresh Fable re-review (round 2), then ponytail-audit, then merge order infra, application, console, customer, admin (admin after brand sign-off). Escalate CONTRACTS/ADR edits (meta-ads.cap-warning, assets_missing position, ADR-B contrast row) to Fable.
Needs owner (not yet notified): approve IAM rows/new stateful resources in infra#40 (all added on new roles; finance_rollup updated in place); add pipeline job building/pushing site-builder-render image before any tenant uses builder mode.

## Position update 2026-11-03 (Run 1 fix round 1 done, round 2 review running)
Fix round 1 (18 findings) pushed on build/run-1-integration. Fable contract/ADR edits done (infra 1c7a916, application 80b0f85; six DECISIONS entries; gen_contracts check passes; no item rejected). Fresh Fable re-review (round 2 + brand guardian + ponytail-audit) running. Next: if verdicts all "merge" and CI green, merge in order infra#40 (needs owner IAM approval first), application#71, console#14, customer#16, admin#24.

## Position update 2026-11-03 (Run 1 round 2 review done, fix round 2 running)
Round 2 verdicts: infra#40 merge; application#71 merge after fixes; admin#24 merge; console#14 merge; customer#16 merge after brand decision. F1-F19 verified fixed. New: HIGH meta-ads LANDING bookings "/boka" -> "/boka-bord" (attribution lost); MED guest-crm HIST+counter non-transactional; MED publishing campaign with no executionArn needs sweep; brand exception for hand-rolled nav Bar in site-kit decided (accepted, documented). Fix round 2 (of max 3) launched. Then fresh Fable re-check of the round-2 commits and merge in order infra#40 (owner IAM approval first), application#71, console#14, admin#24, customer#16.

## Position update 2026-11-03 (Run 1 fix round 2 done, round 3 re-check running)
Fix round 2 pushed (application 83b807b/363256c/168dc78, infra fa55fe7/481a92c/6fde7f2, customer 58bebf7, admin 7a1e0ed..af903e7, console 2f7e120). Adds IAM: meta-ads-jobs states:StartExecution on publish state machine only (owner approval row for infra#40). Fresh Fable re-check + Fable contract edit (start_failed for meta-ads, sweep in ADR-A) running. Next: if "merge" and CI green, merge infra#40 only after owner IAM approval; otherwise exit with Run 1 on dev-ready PRs awaiting that approval.
