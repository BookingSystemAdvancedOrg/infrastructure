# social-posting

Social posting (feature G, `socialPosting`): owners post a dish or tonight's
special to their Facebook Page and Instagram, now or scheduled, using feature
A's Meta connection.

- Decision record: `docs/adr/ADR-G-social-posting.md`; contract: `docs/build/CONTRACTS.md`
  (feature G, sections 0, 4, 5, 6.G, 11, 12 and 13).
- Resources: table `<prefix>social-posting` (PITR, TTL, deletion protection in
  prod), Lambda `social-posting` (routes, publish worker, disconnect
  consumer, purge), Scheduler group `<prefix>social-posting` for
  `post-<postId>` (ActionAfterCompletion DELETE) and its invoke role, bus
  rule on `MetaConnection.Disconnected` with retries and an SQS DLQ, Errors alarm.
- Client: `META_CLIENT` from A's root variable `meta_client` (G declares none).
- IAM (new role only, **owner to approve**): own table CRUD; GetItem/Query on
  the menu table; `s3:GetObject` on `menu-images/*` (presigned GET for
  Meta); **`secretsmanager:GetSecretValue` on A's `booqy/<env>/meta-ads/*`
  (read only, never Put/Create/Delete)**; **`dynamodb:GetItem` on A's
  `<prefix>meta-ads` table** (CONNECTION rows); scheduler Create/Delete on
  its group; `iam:PassRole` on its scheduler role; `lambda:InvokeFunction`
  on its own `social-posting:live` ("Publicera nu"); `events:PutEvents`
  with `events:source = booqy.social-posting`; the tenant-context read
  policy (wiring). Scheduler role: invoke `social-posting:live`.
- No existing role changes (tenant-purge's grant exists since Run 0).
- Routes: `network/api-gateway/social-posting-routes.tf` (8 jwt).
- ECR repository already exists (`module "social_posting_ecr"` in `config.tf`).
