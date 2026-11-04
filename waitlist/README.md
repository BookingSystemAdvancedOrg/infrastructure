# waitlist

Waitlist and walk-in queue (feature F, `waitlist`): one same-day queue per
location; staff offer a freed table (a table hold), guests join from the site
and take the table by SMS link.

- Decision record: `docs/adr/ADR-F-waitlist.md`; contract: `docs/build/CONTRACTS.md`
  (feature F, sections 0, 4, 5, 6.F, 7, 9.4, 10 and 12).
- Resources: table `<prefix>waitlist` (PITR, TTL, deletion protection in prod,
  no stream), Lambda `waitlist` (API, public routes, offer timer, hooks),
  Scheduler group `<prefix>waitlist` for `waitlist-offer-<entryId>`
  (ActionAfterCompletion DELETE) and its invoke role, Errors alarm.
- IAM (**owner to approve**). New role `waitlist`: own table CRUD;
  **item actions on the existing reservation and slot-occupancy tables**
  (BatchGet/Get/Put/Update/Delete/Query, the same set as
  create-pending-reservation, needed because an offer is a table hold);
  Get/Query on the published layout snapshot; **UpdateItem on the existing
  location table limited by `dynamodb:Attributes` to `PK`, `SK`,
  `waitlist`** (publicJoin mirror, CONTRACTS.md 4); GetSecretValue on the
  reservation link key and the Turnstile secret; UpdateItem on the
  request-guard table; `lambda:InvokeFunction` on `notification:live`;
  `scheduler:CreateSchedule/DeleteSchedule` on its group; `iam:PassRole`
  on its scheduler role (PassedToService scheduler); `events:PutEvents`
  with `events:source = booqy.waitlist`; the shared tenant-context and
  staff-check read policies (wiring). Scheduler role: invoke `waitlist:live`.
- No existing role changes here (guest-privacy and tenant-purge invoke
  grants on `waitlist:live` exist since Run 0, CONTRACTS.md 14).
- Routes: `network/api-gateway/waitlist-routes.tf` (6 jwt, 4 public with the
  public throttle).
- ECR repository already exists (`module "waitlist_ecr"` in `config.tf`).
