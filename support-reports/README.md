# support-reports

"Rapportera till Booqy" in Booqy Admin: when an error is Booqy's fault (5xx,
`*_unavailable`, `internal_error`, AccessDenied, unknown codes) the error
note has a one-click report button.

- Application: `functions/support-reports`.
- Routes: `POST /tenant/support/reports` (JWT, owners and staff);
  `GET /platform/support/reports` and
  `POST /platform/support/reports/{reportId}/handled` (operator JWT,
  platform authorizer, the Lambda requires `platform_admin`), straight to
  this integration like the help assistant's operator routes.
- Stored (table `support-reports`, TTL 180 days): tenant id and name, user
  sub and role, page path (no query or fragment; opaque segments replaced),
  time, error code and HTTP status, API request id, app version, user agent.
  Never tokens, passwords, form contents or free text: the body accepts only
  `code`, `status`, `path`, `requestId`, `appVersion`.
- Limits: 10 reports an hour per user (request-guard counters); the same
  report (tenant, user, code, status, path) within 10 minutes is stored and
  emailed once.
- Notification: one SNS message per new report to the platform alerts topic
  (the `alert_emails` subscribers), with a link to Console Reports.
- Resources: Lambda `support-reports` (+ `live` alias, log group 30 days,
  Errors alarm), DynamoDB table `support-reports`, ECR repository
  `support-reports` (config.tf).
- IAM. New role `support-reports`: `dynamodb:PutItem`, `GetItem`, `Query`,
  `UpdateItem`, `DeleteItem` on the support-reports table;
  `dynamodb:UpdateItem` on the request-guard table; `sns:Publish` on the
  platform alerts topic; logs to its own log group. Attached to the shared
  tenant-context policy (`tenant_aware_role_names`). No OIDC or deploy role
  changes.
