# gift-cards (CONTRACTS.md, feature E). Run 0: no resources, locals only.
locals {
  prefix = var.environment == "prod" ? "" : "${var.environment}-"
  name   = "${local.prefix}gift-cards"
}
