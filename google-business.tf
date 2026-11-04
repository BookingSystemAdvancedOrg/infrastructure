# Google Business Profile (google-business/, CONTRACTS.md feature D, Run 2).
module "google_business" {
  source                        = "./google-business"
  environment                   = var.env
  region                        = var.aws_region
  ecr_repository_urls           = { "google-business" = module.google_business_ecr.repository_url, "google-business-jobs" = module.google_business_jobs_ecr.repository_url }
  tenant_table_name             = module.tenant.table_name
  location_table_name           = module.location.table_name
  location_id_index_name        = module.location.location_id_index_name
  reservation_table_name        = module.reservation.table_name
  reservation_table_arn         = module.reservation.table_arn
  order_table_name              = module.order.table_name
  order_table_arn               = module.order.table_arn
  consent_table_name            = module.consent_log.table_name
  consent_table_arn             = module.consent_log.table_arn
  marketing_link_key_secret_arn = module.marketing.link_key_secret_arn
  ses_identity_arn              = local.ses_identity_arn
  from_address                  = local.no_reply_email
  mail_outbox_bucket_name       = local.mail_outbox_bucket
  mail_outbox_bucket_arn        = local.mail_outbox_arn
  event_bus_name                = module.events.bus_name
  event_bus_arn                 = module.events.bus_arn
  alert_topic_arn               = module.alerts.topic_arn
  google_business_client        = var.google_business_client
  admin_app_url                 = local.admin_app_url
}
