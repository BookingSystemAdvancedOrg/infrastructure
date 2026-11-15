# Test sites (owner 2026-11-15): every customer created in the DEV console
# is a test customer with a real, public repo site-<slug> in GitHub org
# BooqyCustomersDev (App "Booqy Test Sites", generated from the public
# BooqyCustomers/site-template). Both branches deploy in the dev account to
# a sandbox of their own (./test-sites): main to https://<slug>.test.booqy.se,
# dev to https://<slug>.test-dev.booqy.se. Real customers (BooqyCustomers,
# prod console) are unchanged. docs/CUSTOMER-SITE-RUNBOOK.md, "Test sites".
#
# Rollout:
#   1. dev.tfvars test_sites_zones = true: the two zones only. Read their name
#      servers (outputs test_sites_main_name_servers / _dev_name_servers).
#   2. prod.tfvars platform_subdomain_delegations gets "test" and "test-dev"
#      (reaches prod with the owner's main merge, or add the NS records by
#      hand first: Terraform adopts them). Check: dig NS test.booqy.se
#   3. dev.tfvars test_sites_enabled = true: certificate, bucket,
#      distribution, connection group, DNS wildcards, boundary, and the test
#      paths in site-repo, the workflows and platform-tenants.

locals {
  test_sites_zones   = var.env != "prod" && var.test_sites_zones
  test_sites_enabled = local.test_sites_zones && var.test_sites_enabled
  # Empty outside phase 2: every consumer treats "" as "no test sites".
  test_sites_main_domain     = local.test_sites_enabled ? var.test_sites_main_domain : ""
  test_sites_dev_domain      = local.test_sites_enabled ? var.test_sites_dev_domain : ""
  test_sites_zone_ids        = local.test_sites_zones ? module.test_sites[0].zone_ids : []
  test_sites_bucket_name     = local.test_sites_enabled ? module.test_sites[0].bucket_name : ""
  test_sites_bucket_arn      = local.test_sites_enabled ? module.test_sites[0].bucket_arn : ""
  test_sites_distribution_id = local.test_sites_enabled ? module.test_sites[0].distribution_id : ""
  test_sites_distribution    = local.test_sites_enabled ? module.test_sites[0].distribution_arn : ""
  test_sites_connection_id   = local.test_sites_enabled ? module.test_sites[0].connection_group_id : ""
  test_sites_connection_arn  = local.test_sites_enabled ? module.test_sites[0].connection_group_arn : ""
  test_sites_boundary_arn    = local.test_sites_enabled ? module.test_sites[0].deploy_boundary_arn : ""
}

module "test_sites" {
  count  = local.test_sites_zones ? 1 : 0
  source = "./test-sites"
  providers = {
    aws           = aws
    aws.us_east_1 = aws.us_east_1
  }

  environment                            = var.env
  main_domain                            = var.test_sites_main_domain
  dev_domain                             = var.test_sites_dev_domain
  enabled                                = var.test_sites_enabled
  menu_image_bucket_regional_domain_name = module.menu_image.bucket_regional_domain_name
}

variable "test_sites_zones" {
  description = "Dev only, phase 1: the hosted zones test_sites_main_domain and test_sites_dev_domain in this account (delegated from prod). Refused in prod."
  type        = bool
  default     = false

  validation {
    condition     = !(var.test_sites_zones && var.env == "prod")
    error_message = "test_sites_zones is dev only."
  }
}

variable "test_sites_enabled" {
  description = "Dev only, phase 2 (after prod delegates the zones): the sandbox and test customers in the dev console. Needs test_sites_zones. Refused in prod."
  type        = bool
  default     = false

  validation {
    condition     = !(var.test_sites_enabled && var.env == "prod")
    error_message = "test_sites_enabled is dev only."
  }
}

variable "test_sites_main_domain" {
  description = "Zone of the main branch's test hosts (<slug>.<this>)"
  type        = string
  default     = "test.booqy.se"
}

variable "test_sites_dev_domain" {
  description = "Zone of the dev branch's test hosts (<slug>.<this>)"
  type        = string
  default     = "test-dev.booqy.se"
}

variable "test_sites_github_org" {
  description = "Dev: GitHub org of the test customers' repos (BooqyCustomersDev). The site-repo function writes test site roles only for repos this org owns."
  type        = string
  default     = ""
}

variable "test_sites_github_org_id" {
  description = "Dev: numeric id of test_sites_github_org (checked with the login before any role trust is written)"
  type        = string
  default     = ""
}

variable "site_template_owner" {
  description = "Org that owns site-template (BooqyCustomers); dev generates test repos from it into test_sites_github_org. Empty: the repo's own org."
  type        = string
  default     = ""
}

variable "site_github_org_id" {
  description = "Numeric id of site_github_org (BooqyCustomers); site-repo checks it with the login. Empty: login only."
  type        = string
  default     = ""
}

output "test_sites_main_name_servers" {
  description = "Dev: name servers of test.<domain>, for prod.tfvars platform_subdomain_delegations[\"test\"]"
  value       = local.test_sites_zones ? module.test_sites[0].main_name_servers : []
}

output "test_sites_dev_name_servers" {
  description = "Dev: name servers of test-dev.<domain>, for prod.tfvars platform_subdomain_delegations[\"test-dev\"]"
  value       = local.test_sites_zones ? module.test_sites[0].dev_name_servers : []
}
