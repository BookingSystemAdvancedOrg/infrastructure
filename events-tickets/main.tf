# events-tickets (CONTRACTS.md, feature K, Run 0 addendum). No resources yet, locals only.
locals {
  prefix = var.environment == "prod" ? "" : "${var.environment}-"
  name   = "${local.prefix}events-tickets"
}
