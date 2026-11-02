# google-business (CONTRACTS.md, feature D). Run 0: no resources, locals only.
locals {
  prefix = var.environment == "prod" ? "" : "${var.environment}-"
  name   = "${local.prefix}google-business"
}
