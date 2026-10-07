# infrastructure

Terraform for the multi-tenant restaurant SaaS platform — DynamoDB, Lambda
(container images), API Gateway, Cognito, Step Functions, S3 + CloudFront
(incl. a multi-tenant distribution for restaurant websites), SES,
EventBridge Scheduler, and the Stripe Connect webhook endpoints.

One deployment per environment (dev, prod) serves **every** restaurant.
Restaurants are tenants created from the operator app - no fork, no
Terraform change, no deploy per customer:

- [docs/MULTI-TENANCY.md](docs/MULTI-TENANCY.md) — how tenancy, isolation, Stripe Connect and domains work
- [docs/PLATFORM-SETUP.md](docs/PLATFORM-SETUP.md) — one-time setup per environment
- [docs/TENANT-ONBOARDING.md](docs/TENANT-ONBOARDING.md) — adding, upgrading, suspending, offboarding a restaurant
- [docs/handoff/BACKEND.md](docs/handoff/BACKEND.md), [docs/handoff/FRONTEND.md](docs/handoff/FRONTEND.md) — what the application and front-end repos implement against this

## CI/CD

Three workflows under `.github/workflows/`:

- `dev.yml` — triggers on `dev` (push + PR), calls the reusable workflow with `environment: dev`
- `prod.yml` — same for `main` → `prod`
- `reusable_cicd.yml` — the actual pipeline

Environment is picked from the branch; dev and prod are **separate AWS
accounts** and, on the Stripe side, the platform Stripe account's sandbox
(dev) vs live mode (prod) — selected purely by which API key the pipeline
exports. Restaurants are Connect accounts under it.

- **PR into `dev` or `main`** → fmt / init / validate / plan only. Read-only — this is the review step, and it also exercises the Stripe key.
- **Push to `dev` / merge to `main`** → full apply: ECR repos first (the `-target` list is derived from `config.tf`'s `module "*_ecr"` blocks — nothing to keep in sync by hand), placeholder Lambda images into any empty repo, the full `terraform apply`, then placeholder front-ends into any empty bucket.

Note: prod applies the moment a PR merges to `main` — no manual approval
gate in this version.

## Configuration split

| | Where |
|---|---|
| Non-secret platform values | `.github/config/project.env`: OIDC role ARNs, state bucket names, region, no-reply email, GitHub org + repo names |
| Per-environment Terraform values | `dev.tfvars` / `prod.tfvars`: operator emails, alert emails, `platform_domain`, plans, default VAT rates, Stripe publishable key, Turnstile site key |
| Secrets | GitHub repo secrets `STRIPE_SECRET_KEY_DEV` / `STRIPE_SECRET_KEY_PROD` (platform Stripe key). Webhook signing secrets are created by Terraform (`payments/stripe`) into Secrets Manager. Set once per environment by hand in Secrets Manager: the Lambdas' Stripe key (`stripe/api-key`), signing provider and Turnstile secrets (`catering/*`) - see docs/PLATFORM-SETUP.md |
| Per-restaurant data | Nowhere in this repo - the tenant table, written by the operator app |

The pipeline authenticates to AWS via OIDC (no long-lived AWS keys
anywhere), assuming the per-account infra role named in `project.env`. The
state bucket, the OIDC provider, and that role are the only resources not
created by this repo — they come from the separate aws-accounts vending
repo, per account, before the first pipeline run.

## Layout

- `config.tf` — root: providers, every module wired together
- `storage/` — DynamoDB tables (each with its access-pattern comments; `dynamodb/tenant` is the control-plane table), ECR repos, S3 buckets, SQS dead-letter queues, Cognito (`cognito` = restaurant users, `cognito-platform` = operators)
- `compute/lambda/` — one module per Lambda function (`pre-token-generation` and the `get-location` public-info handler carry their code here; the rest are images from the application repo)
- `orchestration/tenant-workflows/` — Step Functions: tenant onboarding, custom domain attach/detach, offboarding
- `security/iam/` — one least-privilege role module per Lambda + the GitHub OIDC deploy roles for the app repos
- `security/secrets/` — Secrets Manager secrets (platform Stripe key; catering: signing provider, Turnstile, magic-link key)
- `security/iam/tenant-context/` — the shared read policy every tenant-aware Lambda gets
- `network/` — API Gateway (see `network/api-gateway/ROUTES.md`, generated — run `generate_routes.py` after route changes), CloudFront, SES; `platform-domain/` = Route 53 zone, multi-tenant distribution, SES domain (only when `platform_domain` is set)
- `monitoring/` — SNS alert topic + CloudWatch alarms for the dead-letter queues and their scheduled replay (`dlq-replay`)
- `payments/stripe/` — Stripe webhook endpoints as code (per-environment, event lists as variables)
- `ci/` — placeholder Lambda image + front-ends for bootstrap
- `docs/` — the multi-tenancy docs above, [RESERVATION-PAYMENT-FLOW.md](docs/RESERVATION-PAYMENT-FLOW.md) (card-on-file design), [CATERING-FLOW.md](docs/CATERING-FLOW.md) (catering offer → BankID → payment/invoice contract)
