
variable "env" {
  type        = string
  description = "The environment to deploy to (dev or prod)"
  sensitive   = false
}
variable "aws_region" {
  type        = string
  description = "The AWS region to deploy to"
  sensitive   = false
}
variable "no_reply_email_address" {
  type        = string
  description = "The email address to use for sending no-reply emails"
  sensitive   = false
}
variable "stripe_api_version" {
  type        = string
  description = "Pinned Stripe API version the Lambdas are coded against, e.g. 2026-07-29.dahlia"
  sensitive   = false
}
variable "stripe_secret_key" {
  type        = string
  description = "Secret API key (sk_... or rk_...) of YOUR platform Stripe account - sandbox for dev, live for prod. Restaurants are Connect accounts under it; their keys are never needed. Used by Terraform (webhook endpoints), the onboarding workflow (creating connected accounts) and to seed the platform Stripe secret the Lambdas read."
  sensitive   = true
}
variable "github_org" {
  type        = string
  description = "Shared GitHub organization all OIDC-trusted repos live under - combined with each *_repo variable below to build the \"org/repo-name\" each role's trust policy matches against"
  sensitive   = false
}
variable "customer_frontend_repo" {
  type        = string
  description = "Customer front-end repo name (no org prefix) - trusted by security/iam/oidc/customer-front-end-role's trust policy"
  sensitive   = false
}
variable "admin_frontend_repo" {
  type        = string
  description = "Admin front-end repo name (no org prefix) - trusted by security/iam/oidc/admin-front-end-role's trust policy"
  sensitive   = false
}
variable "backend_repo" {
  type        = string
  description = "Backend repo name (no org prefix) - trusted by security/iam/oidc/back-end-role's trust policy"
  sensitive   = false
}
variable "platform_admin_frontend_repo" {
  type        = string
  description = "Operator console repo name (no org prefix), e.g. booqy-console - holds the operator web app AND the platform-tenants Lambda; trusted by security/iam/oidc/platform-admin-front-end-role to deploy both"
  sensitive   = false
}
variable "demo_request_recipient" {
  description = "Where the public page's \"Boka en demo\" requests are emailed. In the SES sandbox it must be a verified identity (or on a verified domain)."
  type        = string
  sensitive   = false
  default     = "support@ithjalparna.se"
}

variable "support_email_address" {
  description = "Where restaurant owners' replies to news from Booqy Console go (Reply-To); the default on the Mail page's brand template"
  type        = string
  sensitive   = false
  default     = "support@ithjalparna.se"
}

variable "website_repo" {
  type        = string
  description = "Repo name (no org prefix) of the public page on <platform_domain> - trusted by security/iam/oidc/website-deploy-role to deploy it"
  sensitive   = false
  default     = "booqy-website"
}
variable "platform_operator_emails" {
  type        = list(string)
  description = "Platform operators (you) - bootstrapped into the separate operator user pool (MFA required) that alone can call /platform/* to create and manage tenants. Removing an address deletes that operator's account on the next apply."
  sensitive   = false

  validation {
    condition     = length(var.platform_operator_emails) > 0
    error_message = "At least one platform operator is required - otherwise nobody can create tenants."
  }
}
variable "platform_domain" {
  type        = string
  description = "Domain the platform owns, e.g. bokning.example.se. Empty (default) switches off everything that needs it: tenant subdomains (<slug>.<domain>), customer custom domains (CloudFront multi-tenant distribution), restaurang./admin. aliases and the SES sending domain. Setting it creates a Route 53 hosted zone - delegate the domain to the name servers in the platform_domain_name_servers output."
  sensitive   = false
  default     = ""

  validation {
    condition     = var.platform_domain == "" || can(regex("^([a-z0-9]([a-z0-9-]*[a-z0-9])?\\.)+[a-z]{2,}$", var.platform_domain))
    error_message = "platform_domain must be a lowercase domain name like bokning.example.se, or empty."
  }
}
variable "platform_domain_zone_id" {
  type        = string
  description = "ID of an EXISTING Route 53 hosted zone for platform_domain to adopt instead of creating a new one: prod - the zone Route 53 created when the domain was registered (already the domain's name servers); dev - the dev.<domain> zone created by hand and delegated from prod before the first apply (the wildcard certificate validates in it). Empty = Terraform creates the zone."
  sensitive   = false
  default     = ""
}

variable "platform_subdomain_delegations" {
  type        = map(list(string))
  description = "Subdomains of platform_domain served by ANOTHER account's hosted zone: label => that zone's 4 name servers. Prod sets { dev = [...] } so dev.<domain> is answered by the dev account."
  sensitive   = false
  default     = {}

  validation {
    condition = alltrue([
      for label, ns in var.platform_subdomain_delegations :
      can(regex("^[a-z0-9]([a-z0-9-]*[a-z0-9])?$", label)) && length(ns) >= 2
    ])
    error_message = "platform_subdomain_delegations: lowercase labels (e.g. dev), each with at least 2 name servers."
  }
}

variable "tenant_sites_enabled" {
  type        = bool
  description = "Serve restaurant websites (the shared customer-front-end build) on each restaurant's own domain, attached from Booqy Console: CloudFront multi-tenant distribution + connection group, one CNAME per restaurant. Off = custom domains are refused and the platform domain is used only for restaurang. (admin app), admin. (Booqy Console) and mail. (SES)."
  sensitive   = false
  default     = false
}

variable "tenant_subdomains_enabled" {
  type        = bool
  description = "Also give every restaurant <slug>.<platform_domain> at onboarding (*.<domain> record). Needs tenant_sites_enabled. Off = own domains only."
  sensitive   = false
  default     = false
}

variable "plans" {
  type = map(object({
    name          = string
    max_locations = number
    features      = map(bool)
  }))
  description = "Plan catalog (packages you sell). A tenant's limits are copied from its plan when the plan is assigned and can be overridden per tenant from the platform dashboard - no deploy either way. Feature keys: reservations, ordering, catering, terminal (card readers for in-person payments, managed from Booqy Console), marketing (visit statistics and email campaigns to guests who opted in)."
  sensitive   = false
  default = {
    starter = {
      name          = "Starter"
      max_locations = 1
      features      = { reservations = true, ordering = true, catering = false, terminal = true, marketing = false }
    }
    growth = {
      name          = "Growth"
      max_locations = 3
      features      = { reservations = true, ordering = true, catering = true, terminal = true, marketing = true }
    }
  }
}
variable "default_tax_rates" {
  type = map(object({
    display_name = string
    percentage   = number
    inclusive    = bool
  }))
  description = "VAT rates the onboarding workflow creates on every new restaurant's connected Stripe account, keyed by how the Lambdas refer to them (e.g. food, delivery). The resulting txr_ ids are stored per tenant (PROFILE.stripe.taxRates). Set once an accountant has confirmed them; empty means none are created."
  sensitive   = false
  default     = {}
}
variable "cognito_invites_via_ses" {
  type        = bool
  description = "Send Cognito invitation/reset emails through SES (no daily cap, your sender address) instead of Cognito's built-in sender (max 50 emails/day). Turn on once the SES identity is verified and production access is granted - see docs/PLATFORM-SETUP.md."
  sensitive   = false
  default     = false
}
variable "mail_outbox" {
  type        = bool
  description = "Dev only: save every platform email to a private S3 outbox (read in Booqy Console, \"Mail outbox\") instead of sending it through SES - for while the sending domain isn't verified. Must stay false in prod."
  sensitive   = false
  default     = false

  validation {
    condition     = !var.mail_outbox || var.env != "prod"
    error_message = "mail_outbox can't be turned on in prod - emails would never reach guests."
  }
}
variable "dlq_replay_interval_minutes" {
  type        = number
  description = "How often dlq-replay drains the dead-letter queues, in minutes - short in dev to see replays work, longer in prod; keep it under 1440 (24h) so stream records can still be re-read"
  sensitive   = false

  validation {
    condition     = var.dlq_replay_interval_minutes >= 1 && var.dlq_replay_interval_minutes < 1440
    error_message = "dlq_replay_interval_minutes must be between 1 and 1439 (stream records expire after 24 hours)."
  }
}
variable "alert_emails" {
  type        = list(string)
  description = "Email addresses that receive alerts about failed background work (dead-letter queues) (SNS) - each gets a confirmation email after the first apply"
  sensitive   = false
}
variable "turnstile_site_key" {
  type        = string
  description = "Public Cloudflare Turnstile site key of the platform's widget - handed to tenant websites by GET /site-config (the secret key stays in Secrets Manager)"
  sensitive   = false
  default     = ""
}
variable "stripe_publishable_key" {
  type        = string
  description = "Publishable key (pk_test_... in dev, pk_live_... in prod) of the platform Stripe account - not a secret; returned to tenant websites by GET /site-config"
  sensitive   = false
  default     = ""
}

variable "sms_monthly_spend_limit_usd" {
  type        = number
  description = "Account-wide monthly SMS spend limit in USD for this environment's account, alarmed at 80%. Check the current value first (aws sns get-sms-attributes) - a lower value here stops SMS sooner. New AWS accounts have a 1 USD SMS quota; raise it with an AWS support case before setting a higher value. null (default) = the account's SMS settings aren't managed by Terraform"
  sensitive   = false
  default     = null
}

variable "refresh_token_rotation_enabled" {
  description = "Staff app client: rotate refresh tokens on every use. Turn on only after the manage-auth release that uses GetTokensFromRefreshToken is live (docs/COOKIES.md, step 4)."
  type        = bool
  default     = false
}

variable "tenant_data_retention_days" {
  type        = number
  description = "Days an offboarded restaurant's data is kept before tenant-purge deletes it (bookings, orders, menus, layouts, catering requests, marketing, users, menu images). Catering documents and the restaurant's Stripe account are kept."
  sensitive   = false
  default     = 90

  validation {
    condition     = var.tenant_data_retention_days >= 1 && var.tenant_data_retention_days <= 365
    error_message = "tenant_data_retention_days must be between 1 and 365."
  }
}
variable "tenant_purge_schedule" {
  type        = string
  description = "EventBridge Scheduler expression for the tenant-purge sweep (UTC). It only deletes restaurants whose purgeAt has passed, so a missed run just means a later deletion."
  sensitive   = false
  default     = "cron(0 2 * * ? *)"
}
