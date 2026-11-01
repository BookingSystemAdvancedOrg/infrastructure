# guest-crm (CONTRACTS.md, feature C). Run 0: no resources, locals only.
locals {
  prefix = var.environment == "prod" ? "" : "${var.environment}-"
  name   = "${local.prefix}guest-crm"
}
