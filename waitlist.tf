# Waitlist (waitlist/, CONTRACTS.md feature F, Run 2).
module "waitlist" {
  source                               = "./waitlist"
  environment                          = var.env
  region                               = var.aws_region
  ecr_repository_url                   = module.waitlist_ecr.repository_url
  tenant_table_name                    = module.tenant.table_name
  location_table_name                  = module.location.table_name
  location_table_arn                   = module.location.table_arn
  location_id_index_name               = module.location.location_id_index_name
  user_table_name                      = module.user.table_name
  reservation_table_name               = module.reservation.table_name
  reservation_table_arn                = module.reservation.table_arn
  slot_occupancy_table_name            = module.slot_occupancy.table_name
  slot_occupancy_table_arn             = module.slot_occupancy.table_arn
  published_layout_snapshot_table_name = module.published_layout_snapshot.table_name
  published_layout_snapshot_table_arn  = module.published_layout_snapshot.table_arn
  reservation_link_key_secret_arn      = module.reservation_secrets.link_signing_key_secret_arn
  reservation_retention_days           = var.data_retention.booking_days
  turnstile_required                   = var.turnstile_site_key != ""
  turnstile_secret_arn                 = module.catering_secrets.turnstile_secret_arn
  request_guard_table_name             = module.request_guard.table_name
  request_guard_table_arn              = module.request_guard.table_arn
  notification_function_arn            = module.notification_fn.alias_arn
  event_bus_name                       = module.events.bus_name
  event_bus_arn                        = module.events.bus_arn
  alert_topic_arn                      = module.alerts.topic_arn
  site_domain                          = local.site_domain
  customer_site_url                    = local.customer_site_url
  cloudfront_edge_secret               = random_password.cloudfront_edge.result
}
