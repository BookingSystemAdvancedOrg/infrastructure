variable "environment" {
  description = "The environment to deploy to (dev or prod)"
  type        = string
  sensitive   = false
}

variable "role_arn" {
  description = "ARN of the PlatformTenantsFn execution role (security/iam/platform-tenants)"
  type        = string
  sensitive   = true
}

variable "ecr_repository_url" {
  description = "Repository URL of the PlatformTenantsFn ECR repository (storage/ecr/platform-tenants) - the repo itself is owned there, not created in this module"
  type        = string
  sensitive   = true
}

variable "tenant_table_name" {
  description = "Name of the tenant DynamoDB table, passed as an environment variable"
  type        = string
  sensitive   = false
}

variable "location_table_name" {
  description = "Name of the location DynamoDB table, passed as an environment variable"
  type        = string
  sensitive   = false
}

variable "location_id_index_name" {
  description = "Name of the location table's locationId GSI"
  type        = string
  sensitive   = false
}

variable "user_table_name" {
  description = "Name of the user DynamoDB table, passed as an environment variable"
  type        = string
  sensitive   = false
}

variable "user_tenant_index_name" {
  description = "Name of the user table's tenantId GSI"
  type        = string
  sensitive   = false
}

variable "tenant_user_pool_id" {
  description = "ID of the tenant Cognito user pool"
  type        = string
  sensitive   = false
}

variable "owner_group_name" {
  description = "Cognito group of restaurant owners"
  type        = string
  sensitive   = false
}

variable "onboarding_state_machine_arn" {
  description = "ARN of the tenant onboarding state machine, started on tenant creation"
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
  description = "ARN of the platform Stripe API key secret - the handler reads the key at cold start"
  type        = string
  sensitive   = false
}

variable "stripe_api_version" {
  description = "Pinned Stripe API version the handler is coded against"
  type        = string
  sensitive   = false
}

variable "platform_domain" {
  description = "Domain the platform owns (empty = tenant subdomains/custom domains not available yet)"
  type        = string
  sensitive   = false
}

variable "tenant_domain_cname_target" {
  description = "CNAME target a customer points their domain at (CloudFront connection group routing endpoint) - empty while platform_domain is unset"
  type        = string
  sensitive   = false
}

variable "admin_app_url" {
  description = "URL of the shared restaurant admin app (Stripe onboarding return/refresh URLs)"
  type        = string
  sensitive   = false
}

variable "platform_admin_app_url" {
  description = "URL of the platform admin app (Stripe account-link return/refresh URLs for operators)"
  type        = string
  sensitive   = false
}

variable "region" {
  description = "AWS region this Lambda's log group, ECR repository, and image push target live in"
  type        = string
  sensitive   = false
}

variable "operator_user_pool_id" {
  description = "ID of the operator user pool - the Operators page manages its accounts"
  type        = string
  sensitive   = false
}

variable "operator_group_name" {
  description = "Group every operator is added to (and the only one allowed to use this API)"
  type        = string
  sensitive   = false
}

variable "operator_owner_group_name" {
  description = "Group of the operators who are owners: they may change any operator's e-mail and disable or delete an owner"
  type        = string
  sensitive   = false
}

variable "mail_outbox_bucket_name" {
  description = "Dev mail outbox bucket the operator console reads (GET /platform/outbox). Empty string = outbox off (always in prod)."
  type        = string
  sensitive   = false
  default     = ""
}

variable "domain_provision_state_machine_arn" {
  description = "ARN of the domain-provision state machine, passed as an environment variable"
  type        = string
  sensitive   = false
}

variable "domain_documents_bucket_name" {
  description = "Bucket for the registreringsbevis uploaded when buying a .se domain, passed as an environment variable"
  type        = string
  sensitive   = false
}

variable "user_backdrops_bucket_name" {
  description = "Bucket for each operator's own background image (console/<sub>/backdrop), passed as an environment variable"
  type        = string
  sensitive   = false
}

variable "user_backdrops_table_name" {
  description = "Table of each operator's background image library, passed as an environment variable"
  type        = string
  sensitive   = false
}

variable "no_reply_email_address" {
  description = "The no-reply address news to restaurant owners is sent from (Mail page), passed as an environment variable"
  type        = string
}

variable "support_email_address" {
  description = "Default Reply-To for news to restaurant owners, passed as an environment variable"
  type        = string
}

variable "finance_table_name" {
  description = "The finance table (per-day figures, invoice ledger), passed as an environment variable"
  type        = string
}

variable "finance_rollup_alias_arn" {
  description = "Live alias of the finance-rollup Lambda that Rebuild invokes, passed as an environment variable"
  type        = string
}

variable "alert_topic_arn" {
  description = "Operator alert topic the invoicing and dunning tasks report to (environment variable) and the errors alarm notifies"
  type        = string
}

variable "billing_tax_rate_id" {
  description = "Stripe tax rate (txr_...) of Swedish VAT, attached to every subscription (payments/billing)"
  type        = string
}

variable "billing_days_until_due" {
  description = "Days until an emailed subscription invoice is due"
  type        = number
}

variable "billing_suspend_after_days" {
  description = "Days past due before the dunning task suspends a customer (0 = never)"
  type        = number
}

variable "dunning_schedule_expression" {
  description = "When the dunning task runs (cron(), UTC)"
  type        = string
}

variable "scheduler_invoke_role_arn" {
  description = "ARN of the role EventBridge Scheduler assumes to invoke this function for the dunning task"
  type        = string
  sensitive   = true
}


variable "billing_late_fee_sek" {
  description = "Late fee added once per invoice unpaid after the grace period (0 = none)"
  type        = number
}

variable "billing_late_fee_after_days" {
  description = "Days after the due date before the late fee is added"
  type        = number
}

variable "billing_reference_rate_pct" {
  description = "Riksbank reference rate in percent"
  type        = number
}

variable "billing_interest_margin_pct" {
  description = "Percentage points over the reference rate for interest on late payments"
  type        = number
}

variable "billing_notice_months" {
  description = "Months of notice for a subscription customer's cancellation"
  type        = number
}

variable "billing_trial_months" {
  description = "Months after which a try-out customer becomes a subscription automatically (0 = never)"
  type        = number
}

variable "invoicing_schedule_expression" {
  description = "When the invoicing run happens (cron(), UTC): daily; on the 1st it invoices that calendar month in advance, on a start day the rest of the month, otherwise it catches up what is not invoiced yet"
  type        = string
}

variable "site_analytics_table_name" {
  description = "The site-analytics table (booqy.se statistics) the Website page reads; empty when there is no platform domain"
  type        = string
  default     = ""
}

variable "site_repo_function_arn" {
  description = "Live alias of the site-repo function (Website tab), passed as an environment variable"
  type        = string
}

variable "test_main_domain" {
  description = "Dev: the test sites' main host zone (test.<domain>). Empty: no test sites (prod)."
  type        = string
  default     = ""
}

variable "test_dev_domain" {
  description = "Dev: the test sites' dev host zone (test-dev.<domain>). Empty: no test sites (prod)."
  type        = string
  default     = ""
}

variable "site_repos_enabled" {
  description = "Website repo per restaurant on (the GitHub App key is configured)"
  type        = bool
}

variable "billing_days_until_due_no_card" {
  description = "Days to pay an emailed monthly invoice while the restaurant has no card on file"
  type        = number
}

variable "billing_reminder_steps" {
  description = "Days after the due date for the reminders to the restaurant and the operators"
  type        = list(number)
}

variable "billing_final_notice_days" {
  description = "Days after the due date for the final notice (0 = none)"
  type        = number
}

variable "billing_reminder_fee_sek" {
  description = "Påminnelseavgift charged once per late invoice with the first reminder (0 = none)"
  type        = number
}

variable "billing_seller" {
  description = "Booqy's own details on every invoice (name, address, org_number, vat_number, seat, f_skatt)"
  type = object({
    name       = string
    address    = string
    org_number = string
    vat_number = string
    seat       = string
    f_skatt    = bool
  })
}

variable "site_redirect_kvs_arn" {
  description = "Key value store of the restaurant sites' 301s (network/platform-domain); empty: no redirects are written"
  type        = string
  default     = ""
}


variable "print_table_name" {
  description = "The print table (each location's printers and settings), passed as an environment variable"
  type        = string
}

variable "print_server_url" {
  description = "CloudPRNT server URL (<api>/print/cloudprnt) a printer added from Booqy Console is given, passed as an environment variable"
  type        = string
}

variable "manage_user_function_arn" {
  description = "Live alias of the manage-user function (Users tab: invite, edit, role, disable, remove), passed as an environment variable"
  type        = string
}

variable "tenant_account_function_arn" {
  description = "Live alias of the tenant-account function (Users tab: staff permissions), passed as an environment variable"
  type        = string
}

# Dev twins (dev only, docs/DEV-TWINS.md): every real customer's twin in dev,
# set up through the admin's own functions (application shared/console_invoke.py).
variable "dev_twin_function_prefix" {
  description = "Dev only: ARN prefix of this environment's tenant functions (arn:...:function:dev-); the twin seeder invokes <prefix><name>:live. \"\" = dev twins off"
  type        = string
  default     = ""
}

variable "dev_twin_owner_email" {
  description = "Dev only: the twin's owner login, a Booqy team address; {slug} is replaced by the customer's slug (dev+{slug}@booqy.se). Never the restaurant's own email"
  type        = string
  default     = ""
}

variable "dev_twin_stripe_account_id" {
  description = "Dev only: a fully onboarded Stripe TEST-mode connected account (acct_..., not a secret) every twin takes payments with"
  type        = string
  default     = ""
}
