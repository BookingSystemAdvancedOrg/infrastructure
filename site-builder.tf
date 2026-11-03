# Site builder (site-builder/, CONTRACTS.md feature B, Run 1).
module "site_builder" {
  source                   = "./site-builder"
  environment              = var.env
  region                   = var.aws_region
  ecr_repository_urls      = { "site-builder" = module.site_builder_ecr.repository_url, "site-builder-render" = module.site_builder_render_ecr.repository_url }
  tenant_table_name        = module.tenant.table_name
  tenant_table_arn         = module.tenant.table_arn
  location_table_name      = module.location.table_name
  location_id_index_name   = module.location.location_id_index_name
  sites_bucket_name        = module.sites.bucket_name
  request_guard_table_name = module.request_guard.table_name
  request_guard_table_arn  = module.request_guard.table_arn
  site_domain              = local.site_domain
  event_bus_name           = module.events.bus_name
  event_bus_arn            = module.events.bus_arn
  alert_topic_arn          = module.alerts.topic_arn
}
