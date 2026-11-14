# "Rapportera till Booqy" (support-reports/): error reports from Booqy Admin,
# stored 180 days, emailed to the operators through the platform alerts topic
# and listed in Booqy Console (Reports).
module "support_reports_table" {
  source      = "./storage/dynamodb/support-reports"
  environment = var.env
}

module "support_reports" {
  source                   = "./support-reports"
  environment              = var.env
  region                   = var.aws_region
  ecr_repository_url       = module.support_reports_ecr.repository_url
  tenant_table_name        = module.tenant.table_name
  location_table_name      = module.location.table_name
  location_id_index_name   = module.location.location_id_index_name
  table_name               = module.support_reports_table.table_name
  table_arn                = module.support_reports_table.table_arn
  request_guard_table_name = module.request_guard.table_name
  request_guard_table_arn  = module.request_guard.table_arn
  alert_topic_arn          = module.alerts.topic_arn
  console_app_url          = local.platform_admin_app_url
}
