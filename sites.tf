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
  github_org             = var.github_org
  github_app_secret_name = var.github_app_sites_secret_name
  template_repo          = var.site_template_repo
  api_base_url           = module.api_gateway.api_endpoint
  menu_image_base_url    = "https://${module.cloudfront_public.distribution_domain_name}"
  preview_domain         = local.tenant_subdomains_enabled ? var.platform_domain : ""
  stripe_publishable_key = var.stripe_publishable_key
  turnstile_site_key     = var.turnstile_site_key
  alert_topic_arn        = module.alerts.topic_arn
}

variable "github_app_sites_secret_name" {
  description = "Secrets Manager secret with the \"Booqy Sites\" GitHub App key, JSON {\"app_id\", \"private_key\"}: booqy/<env>/github-app-sites, created by hand in each account (docs/CUSTOMER-SITE-RUNBOOK.md). Empty: no site repos, onboarding skips the step."
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
