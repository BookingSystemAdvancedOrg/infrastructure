# tenant-setup

Kom igång: when a restaurant has finished every step (done or skipped) at
every location, Booqy's operators hear about it once, so the website build
can start. The rule: application `docs/SETUP-CHECKLIST.md`.

- Application: `functions/tenant-setup` (`shared/setup_checklist.py`).
- Routes: `GET /tenant/setup`, `PUT /tenant/setup/skips` (JWT, owner only).
- Schedule: `tenant-setup-sweep`, every 15 minutes (`{"setupTask": "sweep"}`):
  re-evaluates every active tenant so Booqy Console's progress stays current.
- Writes (tenant table): `PROFILE.setupState` and `PROFILE.setupCompletedAt`
  only (IAM `dynamodb:Attributes`), `SETUPSKIP#` and `AUDIT#` rows, and the
  `NOTICES` partition Booqy Console's bell reads.
- Notification: `Tenant.SetupCompleted` on the feature bus (source
  `booqy.tenant-setup`) and one SNS message to the platform alerts topic,
  first completion only.
- Resources: Lambda `tenant-setup` (+ `live` alias, log group 30 days,
  Errors alarm), scheduler role and schedule, ECR repository `tenant-setup`
  (config.tf). google-business gained a `table_name` output.
- IAM. New roles only: `tenant-setup` (the access above; GetItem/Query on
  the menu, print, published-layout-snapshot, google-business and
  phone-agent tables; Query on the location table and the user table's
  byTenant index; `events:PutEvents` with source `booqy.tenant-setup`;
  `sns:Publish` on the alerts topic; its own logs; plus the shared
  tenant-context policy) and `tenant-setup-scheduler` (invoke the `live`
  alias). No OIDC or deploy role changes.
