output "provider_arn" {
  description = "ARN of the GitHub Actions OIDC provider - referenced by every OIDC role's trust policy in security/iam/oidc/*-role"
  value       = data.aws_iam_openid_connect_provider.github_actions.arn
}
