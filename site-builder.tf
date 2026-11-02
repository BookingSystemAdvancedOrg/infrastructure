# Site builder (site-builder/, CONTRACTS.md feature B, Run 1).
module "site_builder" {
  source      = "./site-builder"
  environment = var.env
}
