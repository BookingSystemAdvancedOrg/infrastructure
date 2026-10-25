# Card payments at the till (backlog 23): the terminal module (function,
# role, Function URL for Stripe, alarm). ECR repository in config.tf (CI
# derives its bootstrap list from there), routes in
# network/api-gateway/terminal-routes.tf, the Stripe endpoint in
# payments/stripe ("terminal").

module "terminal" {
  source                 = "./terminal"
  environment            = var.env
  region                 = var.aws_region
  ecr_repository_url     = module.terminal_payments_ecr.repository_url
  tenant_table_name      = module.tenant.table_name
  location_table_name    = module.location.table_name
  location_id_index_name = module.location.location_id_index_name
  user_table_name        = module.user.table_name
  order_table_name       = module.order.table_name
  order_table_arn        = module.order.table_arn
  stripe_secret_arn      = module.platform_secrets.stripe_secret_arn
  stripe_api_version     = var.stripe_api_version
  webhook_secret_arn     = module.stripe_webhooks.terminal_webhook_secret_arn
  alert_topic_arn        = module.alerts.topic_arn
}
