# accounting-sync (CONTRACTS.md, feature I). Run 0: no resources, locals only.
locals {
  prefix = var.environment == "prod" ? "" : "${var.environment}-"
  name   = "${local.prefix}accounting-sync"
}
