# google-business

Google Business Profile (feature D, `googleBusiness`): owners connect their
Google profile, Booqy pushes opening hours one way and sends consent-checked
post-visit review requests.

- Decision record: `docs/adr/ADR-D-google-business-profile.md`; contract: `docs/build/CONTRACTS.md`
  (feature D, sections 0, 4, 5, 6.D, 9, 11 and 12).
- Resources: table `<prefix>google-business` (+ sparse GSI `byLinked`),
  Lambdas `google-business` (API D1-D10, hooks platform D11, tenant.purge,
  privacy.export/erase) and `google-business-jobs` (hourly sync, review
  scheduling and sending), Scheduler group `<prefix>google-business` for the
  one-time `gbp-review-<kind>-<sourceId>` schedules (ActionAfterCompletion
  DELETE), hourly schedule `<prefix>google-business-sync`, bus rule on
  `GuestVisit.Recorded` (kind booking/order) with retries and an SQS DLQ
  (shared with the one-time schedules), secret `${prefix}google-business/app`
  (OAuth client, value set by hand), Errors and DLQ alarms.
- Client: `GOOGLE_BUSINESS_CLIENT` from the root `google_business_client`
  (default simulator; refused in prod at runtime).
- IAM (new roles only, **owner to approve**):
  - both functions: own table + GSI CRUD; Secrets Manager create/put/get/
    delete/tag on `booqy/<env>/google-business/*`; get on the app secret;
    `scheduler:DeleteSchedule` on `schedule/<prefix>google-business/*`;
    `events:PutEvents` with `events:source = booqy.google-business`; the
    shared tenant-context read policy (wiring).
  - `google-business-jobs` only: `scheduler:CreateSchedule` on the same group;
    `iam:PassRole` on its scheduler invoke role (PassedToService
    scheduler); `dynamodb:GetItem` on the reservation and order tables
    (contact read at send time through `contactRef`); `dynamodb:Query` on
    the consent log; `secretsmanager:GetSecretValue` on the marketing link
    key (withdraw link); `ses:SendRawEmail` from the no-reply address only;
    `lambda:InvokeFunction` on `notification:live` only (review SMS go through
    notification, CONTRACTS.md 9.4; input `notification_function_arn`, env
    `NOTIFICATION_FUNCTION_NAME`); dev only `s3:PutObject` on the mail outbox `outbox/*`.
  - scheduler invoke role: `lambda:InvokeFunction` on `google-business-jobs:live`,
    `sqs:SendMessage` on the DLQ.
- No existing role changes; the hook callers' invoke grants (guest-privacy,
  tenant-purge, platform-tenants) exist since Run 0.
- Routes: `network/api-gateway/google-business-routes.tf` (10 jwt, 1 operator).
- ECR repositories already exist (`module "google_business_ecr"`,
  `module "google_business_jobs_ecr"` in `config.tf`).
