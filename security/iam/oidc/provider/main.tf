# Account-level identity provider trusting GitHub Actions' OIDC token
# issuer. Not tied to any single repo - customer-front-end-role,
# admin-front-end-role, and back-end-role all reference this same
# provider's ARN in their own trust policy, each scoped to their own repo
# via the sub claim condition instead of needing a separate provider each.
#
# Looked up via data source, not managed as a resource here: this provider
# is a one-per-account primitive that already exists in both the dev and
# prod accounts (created once, out of band, before this module existed).
# Modeling it as a resource caused "EntityAlreadyExists" on every apply
# against an account that already had one - a data source reads the
# existing provider instead of trying to (re)create it, at the cost of
# Terraform no longer managing its lifecycle here (tags/thumbprint/client
# IDs can drift silently if changed outside this repo - if that matters,
# `terraform import` onto a resource block is the alternative).
data "aws_iam_openid_connect_provider" "github_actions" {
  url = "https://token.actions.githubusercontent.com"
}
