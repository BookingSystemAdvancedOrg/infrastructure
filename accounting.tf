# Accounting export (Bokföring in the admin settings): BAS account mapping
# and SIE 4 / CSV export of one verifikation per day. Function, role and
# alarm in ./accounting; ECR repository in config.tf (CI derives its
# bootstrap list from there); routes in network/api-gateway/accounting-routes.tf.

module "accounting" {
  source                       = "./accounting"
  environment                  = var.env
  region                       = var.aws_region
  ecr_repository_url           = module.accounting_ecr.repository_url
  tenant_table_name            = module.tenant.table_name
  location_table_name          = module.location.table_name
  location_table_arn           = module.location.table_arn
  location_id_index_name       = module.location.location_id_index_name
  user_table_name              = module.user.table_name
  order_table_name             = module.order.table_name
  order_table_arn              = module.order.table_arn
  reservation_table_name       = module.reservation.table_name
  reservation_table_arn        = module.reservation.table_arn
  catering_requests_table_name = module.catering_requests.table_name
  catering_requests_table_arn  = module.catering_requests.table_arn
  catering_history_table_name  = module.catering_request_history.table_name
  catering_history_table_arn   = module.catering_request_history.table_arn
  kassa_table_name             = module.kassa.table_name
  kassa_table_arn              = module.kassa.table_arn
  kassa_journal_table_name     = module.kassa.journal_table_name
  kassa_journal_table_arn      = module.kassa.journal_table_arn
  stripe_secret_arn            = module.platform_secrets.stripe_secret_arn
  stripe_api_version           = var.stripe_api_version
  alert_topic_arn              = module.alerts.topic_arn
}
