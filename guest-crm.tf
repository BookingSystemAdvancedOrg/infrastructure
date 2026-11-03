# Guest CRM (guest-crm/, CONTRACTS.md feature C, Run 1).
module "guest_crm" {
  source                 = "./guest-crm"
  environment            = var.env
  region                 = var.aws_region
  ecr_repository_urls    = { "guest-crm" = module.guest_crm_ecr.repository_url, "guest-crm-sync" = module.guest_crm_sync_ecr.repository_url }
  tenant_table_name      = module.tenant.table_name
  location_table_name    = module.location.table_name
  location_id_index_name = module.location.location_id_index_name
  user_table_name        = module.user.table_name
  consent_table_name     = module.consent_log.table_name
  consent_table_arn      = module.consent_log.table_arn
  marketing_table_name   = module.marketing.table_name
  marketing_table_arn    = module.marketing.table_arn
  source_tables = {
    reservation = { name = module.reservation.table_name, arn = module.reservation.table_arn, stream_arn = module.reservation.stream_arn }
    order       = { name = module.order.table_name, arn = module.order.table_arn, stream_arn = module.order.stream_arn }
    catering    = { name = module.catering_requests.table_name, arn = module.catering_requests.table_arn, stream_arn = module.catering_requests.stream_arn }
  }
  event_bus_name  = module.events.bus_name
  event_bus_arn   = module.events.bus_arn
  alert_topic_arn = module.alerts.topic_arn
}
