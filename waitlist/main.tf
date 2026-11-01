# waitlist (CONTRACTS.md, feature F). Run 0: no resources, locals only.
locals {
  prefix = var.environment == "prod" ? "" : "${var.environment}-"
  name   = "${local.prefix}waitlist"
}
