# Personal background image library per user in Booqy Admin (user-backdrop/):
# /me/backdrops. Booqy Console's operators use the same bucket and table
# through platform-tenants (/platform/me/backdrops).
module "user_backdrop" {
  source                 = "./user-backdrop"
  environment            = var.env
  region                 = var.aws_region
  ecr_repository_url     = module.user_backdrop_ecr.repository_url
  tenant_table_name      = module.tenant.table_name
  location_table_name    = module.location.table_name
  location_id_index_name = module.location.location_id_index_name
  bucket_name            = module.user_backdrops.bucket_name
  bucket_arn             = module.user_backdrops.bucket_arn
  table_name             = module.user_backdrops_table.table_name
  table_arn              = module.user_backdrops_table.table_arn
  alert_topic_arn        = module.alerts.topic_arn
}
