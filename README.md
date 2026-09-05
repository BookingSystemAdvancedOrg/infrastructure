# infrastructure

Terraform for the full restaurant platform stack — DynamoDB, Lambda (container
images), API Gateway, Cognito, S3 + CloudFront, SES, EventBridge Scheduler,
and the Stripe webhook endpoints. One deployment of this repo = one customer
environment; see [docs/NEW-CUSTOMER.md](docs/NEW-CUSTOMER.md) for standing up
a new customer from a fork.

## CI/CD

Three workflows under `.github/workflows/`:

- `dev.yml` — triggers on `dev` (push + PR), calls the reusable workflow with `environment: dev`
- `prod.yml` — same for `main` → `prod`
- `reusable_cicd.yml` — the actual pipeline

Environment is picked from the branch; dev and prod are **separate AWS
accounts** and, on the Stripe side, the same Stripe account's sandbox (dev)
vs live mode (prod) — selected purely by which API key the pipeline exports.

- **PR into `dev` or `main`** → fmt / init / validate / plan only. Read-only — this is the review step, and it also exercises the Stripe key.
- **Push to `dev` / merge to `main`** → full apply: ECR repos first (the `-target` list is derived from `config.tf`'s `module "*_ecr"` blocks — nothing to keep in sync by hand), placeholder Lambda images into any empty repo, the full `terraform apply`, then placeholder front-ends into any empty bucket.

Note: prod applies the moment a PR merges to `main` — no manual approval
gate in this version.

## Configuration split

| | Where |
|---|---|
| Non-secret, customer-specific values | `.github/config/project.env` — the one file a fork edits: OIDC role ARNs, state bucket names, region, no-reply email, GitHub org + repo names |
| Per-environment Terraform values | `dev.tfvars` / `prod.tfvars` (super-admin emails) |
| Secrets | GitHub repo secrets: `STRIPE_SECRET_KEY_DEV` (sandbox/test key), `STRIPE_SECRET_KEY_PROD` (live key). That's all — webhook signing secrets are created by Terraform (`payments/stripe`) and wired straight into the receiving Lambdas, never copied anywhere |

The pipeline authenticates to AWS via OIDC (no long-lived AWS keys
anywhere), assuming the per-account infra role named in `project.env`. The
state bucket, the OIDC provider, and that role are the only resources not
created by this repo — they come from the separate aws-accounts vending
repo, per account, before the first pipeline run.

## Layout

- `config.tf` — root: providers, every module wired together
- `storage/` — DynamoDB tables (each with its access-pattern comments), ECR repos, S3 buckets, Cognito
- `compute/lambda/` — one module per Lambda function
- `security/iam/` — one least-privilege role module per Lambda + the GitHub OIDC deploy roles for the app repos
- `network/` — API Gateway (see `network/api-gateway/ROUTES.md`, generated — run `generate_routes.py` after route changes), CloudFront, Route53, SES
- `payments/stripe/` — Stripe webhook endpoints as code (per-environment, event lists as variables)
- `ci/` — placeholder Lambda image + front-ends for bootstrap
- `docs/` — [NEW-CUSTOMER.md](docs/NEW-CUSTOMER.md) (fork-to-deployed runbook), [RESERVATION-PAYMENT-FLOW.md](docs/RESERVATION-PAYMENT-FLOW.md) (card-on-file design)
