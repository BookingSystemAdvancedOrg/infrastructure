# Site languages (site-translate/): POST /translate, Amazon Translate with a
# shared cache table, for the restaurant sites' language switcher.
module "site_translate" {
  source                   = "./site-translate"
  environment              = var.env
  region                   = var.aws_region
  ecr_repository_url       = module.site_translate_ecr.repository_url
  tenant_table_name        = module.tenant.table_name
  tenant_table_arn         = module.tenant.table_arn
  request_guard_table_name = module.request_guard.table_name
  request_guard_table_arn  = module.request_guard.table_arn
  alert_topic_arn          = module.alerts.topic_arn
  site_waf_secret          = random_password.site_waf_edge.result
  cloudfront_edge_secret   = random_password.cloudfront_edge.result
  ip_requests_per_5min     = var.site_translate_ip_requests_per_5min
  ip_chars_per_hour        = var.site_translate_ip_chars_per_hour
  tenant_chars_per_30d     = var.site_translate_tenant_chars_per_30d
  global_chars_per_30d     = var.site_translate_global_chars_per_30d
}
