# user-backdrop

Personal background image library per signed-in user in Booqy Admin (shown
blurred behind the glass UI, follows the user across devices), up to 20.

- Application: `functions/user-backdrop` (Pillow makes the thumbnails).
- Routes (JWT, owners and staff): `GET /me/backdrops`,
  `POST /me/backdrops/upload` (presigned POST: JPEG, PNG or WebP, 1 B to
  10 MB, 300 s), `POST /me/backdrops/{id}/complete` (checks the upload,
  writes a ~400 px WebP thumbnail and the item), `PUT /me/backdrops/selected`,
  `DELETE /me/backdrops/{id}`.
- Storage: bucket `[<env>-]user-backdrops-<account>` (storage/s3/user-backdrops),
  `admin/<tenantId>/<sub>/backdrops/<id>` and `<id>.thumb.webp`; table
  `[<env>-]user-backdrops` (storage/dynamodb/user-backdrops), PK
  `USER#<tenantId>#<sub>`, SK `IMG#<id>` / `SELECTED`. Booqy Console's
  operators: `console/<sub>/backdrops/...`, PK `OPERATOR#<sub>`, through
  platform-tenants.
- Deleted with the user (manage-user) and the restaurant (tenant-purge).
- IAM: role `user-backdrop`: `s3:PutObject`, `s3:GetObject`,
  `s3:DeleteObject` on `<bucket>/admin/*`; `dynamodb:Query`, `GetItem`,
  `PutItem`, `UpdateItem`, `DeleteItem` on the table; logs to its own log
  group; the shared tenant-context policy through the wiring output.
