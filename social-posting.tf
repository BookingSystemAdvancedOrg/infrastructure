# Social posting (social-posting/, CONTRACTS.md feature G, Run 2).
module "social_posting" {
  source                        = "./social-posting"
  environment                   = var.env
  region                        = var.aws_region
  ecr_repository_url            = module.social_posting_ecr.repository_url
  tenant_table_name             = module.tenant.table_name
  location_table_name           = module.location.table_name
  location_id_index_name        = module.location.location_id_index_name
  menu_table_name               = module.menu.table_name
  menu_table_arn                = module.menu.table_arn
  menu_image_bucket_name        = module.menu_image.bucket_name
  menu_image_bucket_arn         = module.menu_image.bucket_arn
  meta_ads_table_name           = module.meta_ads.table_name
  meta_ads_table_arn            = module.meta_ads.table_arn
  meta_ads_tenant_secret_prefix = module.meta_ads.tenant_secret_prefix
  meta_client                   = var.meta_client
  event_bus_name                = module.events.bus_name
  event_bus_arn                 = module.events.bus_arn
  alert_topic_arn               = module.alerts.topic_arn
}
