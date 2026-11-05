# Personalliggare (personalliggare/, CONTRACTS.md feature H, Run 2).
# NEEDS LEGAL REVIEW before the entitlement is turned on for any tenant.
module "personalliggare" {
  source                 = "./personalliggare"
  environment            = var.env
  region                 = var.aws_region
  ecr_repository_url     = module.personalliggare_ecr.repository_url
  tenant_table_name      = module.tenant.table_name
  location_table_name    = module.location.table_name
  location_id_index_name = module.location.location_id_index_name
  user_table_name        = module.user.table_name
  event_bus_name         = module.events.bus_name
  event_bus_arn          = module.events.bus_arn
  alert_topic_arn        = module.alerts.topic_arn
}
