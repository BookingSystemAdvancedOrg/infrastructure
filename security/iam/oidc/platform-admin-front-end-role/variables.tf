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

variable "platform_admin_bucket_arn" {
  description = "ARN of the platform admin front-end asset S3 bucket (storage/s3/platform-admin-front-end-asset) this pipeline deploys to"
  type        = string
  sensitive   = false
}

variable "cloudfront_distribution_arn" {
  description = "ARN of the platform admin CloudFront distribution (network/cloudfront/platform-admin) this pipeline invalidates after deploying"
  type        = string
  sensitive   = false
}

variable "api_ecr_repository_arn" {
  description = "ARN of the platform-tenants ECR repository the sbs-admin pipeline pushes the API image to"
  type        = string
  sensitive   = false
}

variable "api_function_arn" {
  description = "ARN of the platform-tenants Lambda the sbs-admin pipeline updates after pushing the image"
  type        = string
  sensitive   = false
}

variable "codedeploy_app_arn" {
  description = "ARN of the CodeDeploy application releases run in (orchestration/lambda-releases)"
  type        = string
  sensitive   = false
}

variable "codedeploy_deployment_group_arn" {
  description = "ARN of platform-tenants' CodeDeploy deployment group - the only one this role may deploy to"
  type        = string
  sensitive   = false
}

variable "alert_topic_arn" {
  description = "Platform alerts SNS topic - release results are emailed through it"
  type        = string
  sensitive   = false
}
