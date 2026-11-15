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

## Switching dev to the real Google client

The real client (`application/shared/google_business_real.py`) is built and
tested against mocked HTTP; dev and prod keep `google_business_client =
"simulator"` until Booqy's Google Cloud project has Business Profile API
access (a quota of 0 means access is not granted yet). To switch dev:

1. In Google Cloud: enable the My Business Account Management API and the
   My Business Business Information API, create an OAuth 2.0 web client and
   add the redirect URI `https://restaurang.dev.booqy.se/installningar?google=1`
   (must match `GOOGLE_REDIRECT_URI` exactly). Scope used:
   `https://www.googleapis.com/auth/business.manage`.
2. In Secrets Manager (dev account), set the value of `dev-google-business/app`
   by hand to `{"clientId": "...", "clientSecret": "..."}`. Never commit it.
3. On the OAuth consent screen (Google Auth Platform, Audience), set the
   publishing status to "In production", or at least add the owner's Google
   account as a test user. An app left in "Testing" gets refresh tokens that
   expire after 7 days, which shows up as a seemingly random `needs_reauth`.
4. Set `google_business_client = "real"` in `dev.tfvars` and let CI plan and
   apply. No IAM change is needed: both roles already read the app secret and
   manage `booqy/<env>/google-business/*`.
5. A running container caches the OAuth client: after rotating the secret,
   publish a new Lambda version (any deploy) or wait for new containers.

Prod: `google_business_client = "real"` fails the plan (variable validation
in `google-business/variables.tf`) until `google_business_prod_released =
true` is also set in `prod.tfvars`, which is the owner's release. Errors a
retry cannot fix (quota 0, API disabled, wrong OAuth client, no access) are
answered 409 `google_rejected` with `field` naming the cause; only Google
rate limits, 5xx and timeouts are 502 `google_unavailable` with `retryAfter`.

