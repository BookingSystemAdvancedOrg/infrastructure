# personalliggare (CONTRACTS.md, feature H). Run 0: no resources, locals only.
locals {
  prefix = var.environment == "prod" ? "" : "${var.environment}-"
  name   = "${local.prefix}personalliggare"
}
