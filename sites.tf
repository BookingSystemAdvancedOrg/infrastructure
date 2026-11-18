# Restaurant websites, one repo per customer (site-<slug>): sites bucket,
# deploy boundary and the site-repo function in ./sites. ECR repository in
# config.tf (CI derives its bootstrap list from there). The onboarding and
# offboarding workflows call site-repo (orchestration/tenant-workflows);
# Booqy Console calls it through platform-tenants (Website tab).

module "sites" {
  source                 = "./sites"
  environment            = var.env
  region                 = var.aws_region
  ecr_repository_url     = module.site_repo_ecr.repository_url
  tenant_table_name      = module.tenant.table_name
  tenant_table_arn       = module.tenant.table_arn
  distribution_arn       = local.tenant_sites_enabled ? module.platform_domain[0].multitenant_distribution_arn : ""
  oidc_provider_arn      = module.github_oidc_provider.provider_arn
  github_org             = var.site_github_org != "" ? var.site_github_org : var.github_org
  github_app_secret_name = var.github_app_sites_secret_name
  template_repo          = var.site_template_repo
  template_owner         = var.site_template_owner
  github_org_id          = var.site_github_org_id
  # Dev: test customers in the test org, deployed to the sandbox (test-sites.tf)
  test_github_org        = local.test_sites_enabled ? var.test_sites_github_org : ""
  test_github_org_id     = local.test_sites_enabled ? var.test_sites_github_org_id : ""
  test_bucket_name       = local.test_sites_bucket_name
  test_boundary_arn      = local.test_sites_boundary_arn
  test_kvs_arn           = local.test_sites_kvs_arn
  test_main_domain       = local.test_sites_main_domain
  test_dev_domain        = local.test_sites_dev_domain
  api_base_url           = module.api_gateway.api_endpoint
  menu_image_base_url    = "https://${module.cloudfront_public.distribution_domain_name}"
  preview_domain         = local.tenant_subdomains_enabled ? var.platform_domain : ""
  stripe_publishable_key = var.stripe_publishable_key
  alert_topic_arn        = module.alerts.topic_arn
  # A repo is born in prod; prod sets up the dev side through one narrow
  # role in dev (sites/main.tf, booqy-sites-prod-link).
  link_prod_account_id          = var.env == "prod" ? "" : var.site_link_prod_account_id
  link_dev_account_id           = var.env == "prod" ? var.site_link_dev_account_id : ""
  platform_tenants_function_arn = "arn:aws:lambda:${var.aws_region}:${data.aws_caller_identity.current.account_id}:function:${var.env == "prod" ? "platform-tenants" : "${var.env}-platform-tenants"}"
}

variable "github_app_sites_secret_name" {
  description = "Secrets Manager secret with the GitHub App key, JSON {\"app_id\", \"private_key\"}: booqy/<env>/github-app-sites, created by hand in each account (docs/CUSTOMER-SITE-RUNBOOK.md). In prod the \"Booqy Customer Sites\" App (BooqyCustomers); in dev ONLY the \"Booqy Test Sites\" App (BooqyCustomersDev): dev never holds the Customer Sites key. Empty: no site repos, onboarding skips the step."
  type        = string
  default     = ""
}

variable "site_github_org" {
  description = "GitHub organisation the restaurant site repos (site-<slug>) and site-template live in, apart from the platform repos. Only the site-repo function uses it (create, configure, archive, delete); the platform OIDC trusts keep var.github_org. Empty: var.github_org."
  type        = string
  default     = ""
}

variable "site_template_repo" {
  description = "Repo (no org) every restaurant site repo is generated from"
  type        = string
  default     = "site-template"
}


variable "per_tenant_sites" {
  description = "Serve every restaurant domain from its own site (sites/<tenantId>/, repo site-<slug>) instead of the shared customer-front-end build. Turn on once every active restaurant with a domain has a deployed site repo."
  type        = bool
  default     = false
}

variable "site_link_prod_account_id" {
  description = "Dev: the prod account allowed to set up the dev side of restaurant sites (role booqy-sites-prod-link). Empty: none."
  type        = string
  default     = ""
}

variable "site_link_dev_account_id" {
  description = "Prod: the dev account whose booqy-sites-prod-link role prod's site-repo assumes for the dev side of a new site. Empty: prod sets up prod only."
  type        = string
  default     = ""
}
