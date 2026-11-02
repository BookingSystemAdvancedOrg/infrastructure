# phone-agent (CONTRACTS.md, feature L, Run 0 addendum). No resources yet, locals only.
locals {
  prefix = var.environment == "prod" ? "" : "${var.environment}-"
  name   = "${local.prefix}phone-agent"
}
