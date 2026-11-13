# user-backdrop

Own background image per signed-in user in Booqy Admin (shown blurred behind
the glass UI, follows the user across devices).

- Application: `functions/user-backdrop`.
- Routes (JWT, owners and staff): `GET /me/backdrop` (presigned GET, 1 hour,
  or null), `POST /me/backdrop/upload` (presigned POST: JPEG, PNG or WebP,
  1 B to 10 MB, 300 s), `DELETE /me/backdrop` (204, idempotent).
- Storage: bucket `[<env>-]user-backdrops-<account>` (storage/s3/user-backdrops),
  one object per user at `admin/<tenantId>/<sub>/backdrop`. Booqy Console's
  operators use `console/<sub>/backdrop` through platform-tenants.
- Deleted with the user (manage-user) and the restaurant (tenant-purge).
- IAM: role `user-backdrop`: `s3:PutObject`, `s3:GetObject`,
  `s3:DeleteObject` on `<bucket>/admin/*`; logs to its own log group; the
  shared tenant-context policy (tenant table read) through the wiring output.
