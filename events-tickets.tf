# Events and tickets (events-tickets/, CONTRACTS.md feature K, Run 0 addendum, built in Run 2).
module "events_tickets" {
  source                    = "./events-tickets"
  environment               = var.env
  region                    = var.aws_region
  ecr_repository_url        = module.events_tickets_ecr.repository_url
  tenant_table_name         = module.tenant.table_name
  location_table_name       = module.location.table_name
  location_id_index_name    = module.location.location_id_index_name
  user_table_name           = module.user.table_name
  stripe_secret_arn         = module.platform_secrets.stripe_secret_arn
  stripe_api_version        = var.stripe_api_version
  turnstile_required        = var.turnstile_site_key != ""
  turnstile_secret_arn      = module.catering_secrets.turnstile_secret_arn
  request_guard_table_name  = module.request_guard.table_name
  request_guard_table_arn   = module.request_guard.table_arn
  notification_function_arn = module.notification_fn.alias_arn
  event_bus_name            = module.events.bus_name
  event_bus_arn             = module.events.bus_arn
  alert_topic_arn           = module.alerts.topic_arn
  site_domain               = local.site_domain
  customer_site_url         = local.customer_site_url
  cloudfront_edge_secret    = random_password.cloudfront_edge.result
}
