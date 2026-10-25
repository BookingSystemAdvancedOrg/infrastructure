# Kassa, the till (feature "kassa", off by default): tables, function, role,
# alarm in ./kassa. ECR repository in config.tf (CI derives its bootstrap
# list from there), routes in network/api-gateway/kassa-routes.tf.

module "kassa" {
  source                 = "./kassa"
  environment            = var.env
  region                 = var.aws_region
  ecr_repository_url     = module.kassa_ecr.repository_url
  tenant_table_name      = module.tenant.table_name
  location_table_name    = module.location.table_name
  location_id_index_name = module.location.location_id_index_name
  user_table_name        = module.user.table_name
  menu_table_name        = module.menu.table_name
  menu_table_arn         = module.menu.table_arn
  order_table_name       = module.order.table_name
  order_table_arn        = module.order.table_arn
  print_table_name       = module.print.table_name
  print_table_arn        = module.print.table_arn
  stripe_secret_arn      = module.platform_secrets.stripe_secret_arn
  stripe_api_version     = var.stripe_api_version
  alert_topic_arn        = module.alerts.topic_arn
  certified              = var.kassa_certified
}

variable "kassa_certified" {
  description = "Switch Kassa's \"Testläge - inte ett certifierat kassaregister än\" label off. Only with a certified control system connected and a manufacturer's declaration filed (application/docs/KASSA-REQUIREMENTS.md); the simulator ignores it."
  type        = bool
  default     = false
}
