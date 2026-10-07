variable "environment" {
  description = "The environment to deploy to (dev or prod)"
  type        = string
  sensitive   = false
}

variable "oidc_provider_arn" {
  description = "ARN of the GitHub Actions OIDC provider (security/iam/oidc/provider)"
  type        = string
  sensitive   = false
}

variable "github_repo" {
  description = "GitHub repo this role trusts, as \"org/repo-name\" - used in the trust policy's sub claim condition"
  type        = string
  sensitive   = false
}

variable "region" {
  description = "AWS region the ECR repositories and Lambda functions this role deploys to live in"
  type        = string
  sensitive   = false
}

variable "codedeploy_app_name" {
  description = "CodeDeploy application releases run in (orchestration/lambda-releases)"
  type        = string
  sensitive   = false
}

variable "alert_topic_arn" {
  description = "Platform alerts SNS topic - release results are emailed through it"
  type        = string
  sensitive   = false
}
