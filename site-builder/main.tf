# site-builder (CONTRACTS.md, feature B). Run 0: no resources, locals only.
locals {
  prefix = var.environment == "prod" ? "" : "${var.environment}-"
  name   = "${local.prefix}site-builder"
}
