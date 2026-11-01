# social-posting (CONTRACTS.md, feature G). Run 0: no resources, locals only.
locals {
  prefix = var.environment == "prod" ? "" : "${var.environment}-"
  name   = "${local.prefix}social-posting"
}
