# meta-ads (CONTRACTS.md, feature A). Run 0: no resources, locals only.
locals {
  prefix = var.environment == "prod" ? "" : "${var.environment}-"
  name   = "${local.prefix}meta-ads"
}
