# dish-margin (CONTRACTS.md, feature J). Run 0: no resources, locals only.
locals {
  prefix = var.environment == "prod" ? "" : "${var.environment}-"
  name   = "${local.prefix}dish-margin"
}
