# Account-level identity provider trusting GitHub Actions' OIDC token
# issuer. Not tied to any single repo - customer-front-end-role,
# admin-front-end-role, and back-end-role all reference this same
# provider's ARN in their own trust policy, each scoped to their own repo
# via the sub claim condition instead of needing a separate provider each.
#
# Safe to create once per AWS account: dev and prod are separate AWS
# accounts here, so each environment's own apply creates its own provider
# independently - no "already exists" conflict the way there would be if
# both environments shared one account.
resource "aws_iam_openid_connect_provider" "github_actions" {
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]

  # Required by this resource, but as of mid-2023 AWS validates GitHub's
  # OIDC JWKS endpoint against its own trusted root CA bundle rather than
  # checking this value for GitHub's specific provider - kept as the
  # well-known GitHub Actions thumbprint for compatibility, not because
  # AWS relies on it to verify anything anymore.
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]

  tags = {
    Environment = var.environment
  }
}
