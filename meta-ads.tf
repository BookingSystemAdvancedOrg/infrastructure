# Meta ads (meta-ads/, CONTRACTS.md feature A, Run 1).
module "meta_ads" {
  source                    = "./meta-ads"
  environment               = var.env
  region                    = var.aws_region
  ecr_repository_urls       = { "meta-ads" = module.meta_ads_ecr.repository_url, "meta-ads-jobs" = module.meta_ads_jobs_ecr.repository_url }
  tenant_table_name         = module.tenant.table_name
  tenant_table_arn          = module.tenant.table_arn
  location_table_name       = module.location.table_name
  location_id_index_name    = module.location.location_id_index_name
  user_table_name           = module.user.table_name
  user_table_arn            = module.user.table_arn
  user_tenant_index_name    = module.user.tenant_index_name
  menu_table_name           = module.menu.table_name
  menu_table_arn            = module.menu.table_arn
  marketing_table_name      = module.marketing.table_name
  marketing_table_arn       = module.marketing.table_arn
  menu_image_bucket_name    = module.menu_image.bucket_name
  menu_image_bucket_arn     = module.menu_image.bucket_arn
  notification_function_arn = module.notification_fn.alias_arn
  event_bus_name            = module.events.bus_name
  event_bus_arn             = module.events.bus_arn
  alert_topic_arn           = module.alerts.topic_arn
  meta_client               = var.meta_client
  bedrock_client            = var.bedrock_client
  bedrock_model_id          = var.bedrock_model_id
  admin_app_url             = local.admin_app_url
  site_domain               = local.site_domain
}
