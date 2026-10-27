variable "environment" {
  description = "The environment to deploy to (dev or prod)"
  type        = string
  sensitive   = false
}

variable "tenant_table_arn" {
  description = "ARN of the tenant DynamoDB table (storage/dynamodb/tenant)"
  type        = string
  sensitive   = false
}

variable "location_table_arn" {
  description = "ARN of the location DynamoDB table"
  type        = string
  sensitive   = false
}

variable "user_table_arn" {
  description = "ARN of the user DynamoDB table"
  type        = string
  sensitive   = false
}

variable "tenant_user_pool_arn" {
  description = "ARN of the tenant Cognito user pool (storage/cognito)"
  type        = string
  sensitive   = false
}

variable "onboarding_state_machine_arn" {
  description = "ARN of the tenant onboarding state machine"
  type        = string
  sensitive   = false
}

variable "domain_attach_state_machine_arn" {
  description = "ARN of the custom-domain attach state machine"
  type        = string
  sensitive   = false
}

variable "domain_detach_state_machine_arn" {
  description = "ARN of the custom-domain detach state machine"
  type        = string
  sensitive   = false
}

variable "offboarding_state_machine_arn" {
  description = "ARN of the tenant offboarding state machine"
  type        = string
  sensitive   = false
}

variable "stripe_secret_arn" {
  description = "ARN of the platform Stripe API key secret (security/secrets/platform)"
  type        = string
  sensitive   = false
}

variable "region" {
  description = "AWS region this Lambda's log group lives in"
  type        = string
  sensitive   = false
}

variable "operator_user_pool_arn" {
  description = "ARN of the operator user pool (storage/cognito-platform) - operators manage each other's accounts"
  type        = string
  sensitive   = false
}

variable "mail_outbox_bucket_arn" {
  description = "ARN of the dev mail outbox bucket (empty = no outbox, always in prod) - list/read outbox/* for GET /platform/outbox"
  type        = string
  sensitive   = false
  default     = ""
}

variable "mail_outbox_enabled" {
  description = "Whether the dev mail outbox exists (plain bool so the policy count is known at plan time, unlike the bucket ARN)"
  type        = bool
  sensitive   = false
  default     = false
}

variable "domain_provision_state_machine_arn" {
  description = "ARN of the domain-provision state machine (bought / connected restaurant domains)"
  type        = string
  sensitive   = false
}

variable "domains_enabled" {
  description = "Restaurant domains are on (tenant_sites_enabled): grant Route 53 Domains, hosted zone and registreringsbevis access"
  type        = bool
  sensitive   = false
  default     = false
}

variable "domain_documents_bucket_arn" {
  description = "ARN of the registreringsbevis bucket (storage/s3/domain-documents)"
  type        = string
  sensitive   = false
}

variable "platform_zone_id" {
  description = "Hosted zone of the platform domain - this role may never change it. Empty while no platform domain is set"
  type        = string
  sensitive   = false
  default     = ""
}

variable "ses_identity_arn" {
  description = "ARN of the SES identity the no-reply address sends through (news to restaurant owners from Booqy Console)"
  type        = string
}

variable "from_address" {
  description = "The no-reply address news is sent from - the only From the recipient-identity grant allows"
  type        = string
}

variable "finance_table_arn" {
  description = "The finance table (per-day figures, invoice ledger) the Finance page reads and Stripe imports write"
  type        = string
}

variable "finance_rollup_lambda_arn" {
  description = "The finance-rollup Lambda that Rebuild in Booqy Console invokes for a date range"
  type        = string
}

variable "alert_topic_arn" {
  description = "Operator alert topic: the dunning task reports suspensions and resumptions there"
  type        = string
}

variable "site_repo_function_arn" {
  description = "Live alias of the site-repo function (Website tab)"
  type        = string
}
