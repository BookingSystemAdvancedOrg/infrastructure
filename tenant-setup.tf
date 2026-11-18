# Kom igång (tenant-setup/): the one "setup finished" rule for a restaurant,
# the checklist Booqy Admin shows, and the one notice to the operators
# (Booqy Console bell, alerts topic email, Tenant.SetupCompleted event).
module "tenant_setup" {
  source                               = "./tenant-setup"
  environment                          = var.env
  region                               = var.aws_region
  ecr_repository_url                   = module.tenant_setup_ecr.repository_url
  tenant_table_name                    = module.tenant.table_name
  tenant_table_arn                     = module.tenant.table_arn
  location_table_name                  = module.location.table_name
  location_table_arn                   = module.location.table_arn
  location_id_index_name               = module.location.location_id_index_name
  user_table_name                      = module.user.table_name
  user_table_arn                       = module.user.table_arn
  user_tenant_index_name               = module.user.tenant_index_name
  menu_table_name                      = module.menu.table_name
  menu_table_arn                       = module.menu.table_arn
  print_table_name                     = module.print.table_name
  print_table_arn                      = module.print.table_arn
  published_layout_snapshot_table_name = module.published_layout_snapshot.table_name
  published_layout_snapshot_table_arn  = module.published_layout_snapshot.table_arn
  google_business_table_name           = module.google_business.table_name
  phone_agent_table_name               = module.phone_agent.table_name
  event_bus_name                       = module.events.bus_name
  event_bus_arn                        = module.events.bus_arn
  alert_topic_arn                      = module.alerts.topic_arn
  console_app_url                      = local.platform_admin_app_url
}
