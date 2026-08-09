# infrastructure
this is the infrastructure blueprint

## CI/CD

One workflow, `.github/workflows/terraform.yml`, authenticating to AWS via OIDC (no long-lived AWS keys stored anywhere). Environment is picked from the branch: `main` → `prod`, `dev` → `dev`.

- **PR into `main` or `dev`** → fmt/init/validate/plan only. Read-only, nothing applied — this is your review step.
- **Push to `main`** (i.e. a PR merges) → full run including `terraform apply` against `prod`.
- **Push to `dev`** → full run including `terraform apply` against `dev`.

### Config split

| | Where | Example |
|---|---|---|
| Non-secret values | `.github/config/{dev,prod}.env`, `{dev,prod}.tfbackend` — committed to the repo | `TF_BACKEND_CONFIG`, S3 bucket/key |
| Secret values | GitHub Environment secrets (Settings > Environments > *env* > Secrets), named `OIDC_ROLE_ARN` in both `dev` and `prod` with different values | the IAM role CI assumes for that environment |

The job targets the resolved `dev`/`prod` GitHub Environment, so `secrets.OIDC_ROLE_ARN` automatically resolves to the right role for the branch being built. AWS region is hardcoded to `eu-north-1` in the workflow (matches the single-region provider setup in `config.tf`).

### Setup checklist (after forking)

1. Create an AWS IAM OIDC provider for `token.actions.githubusercontent.com` (once per AWS account, skip if it already exists).
2. Create an IAM role per environment, trust policy scoped to `repo:<org>/<repo>:*` (or tighter).
3. In GitHub, create two Environments named `dev` and `prod` (Settings > Environments). In each, add an Environment secret named `OIDC_ROLE_ARN` with that environment's role ARN.
4. Fill in the S3 state bucket + region in `dev.tfbackend` / `prod.tfbackend` (buckets must already exist — Terraform doesn't bootstrap its own backend).
5. Open a PR to confirm the workflow runs cleanly against `dev`, then merge to `main` to deploy `prod`.

Note: prod deploys automatically the moment a PR merges to `main` — there's no manual approval gate in this version. Since the job already targets the `prod` GitHub Environment, adding one later is just a matter of turning on required reviewers there — no workflow changes needed.
