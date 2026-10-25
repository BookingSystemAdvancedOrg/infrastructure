# Kitchen printing (issue 2): the print table and the printing module
# (functions, roles, order stream mapping, sweep schedule, alarms). ECR
# repositories are in config.tf (CI derives its bootstrap list from there),
# routes in network/api-gateway/printing-routes.tf.

module "print" {
  source      = "./storage/dynamodb/print"
  environment = var.env
}

module "printing" {
  source      = "./printing"
  environment = var.env
  region      = var.aws_region
  ecr_repository_urls = {
    "print-jobs"   = module.print_jobs_ecr.repository_url
    "print-device" = module.print_device_ecr.repository_url
  }
  tenant_table_name        = module.tenant.table_name
  location_table_name      = module.location.table_name
  location_id_index_name   = module.location.location_id_index_name
  user_table_name          = module.user.table_name
  order_table_name         = module.order.table_name
  order_table_arn          = module.order.table_arn
  order_stream_arn         = module.order.stream_arn
  print_table_name         = module.print.table_name
  print_table_arn          = module.print.table_arn
  print_stream_dlq_arn     = module.dead_letter.print_stream_dlq_arn
  request_guard_table_name = module.request_guard.table_name
  request_guard_table_arn  = module.request_guard.table_arn
  # The printer polls API Gateway directly (TLS 1.2, no CloudFront): the
  # admin shows this plus /<deviceId> as the CloudPRNT server URL.
  print_server_url = "${module.api_gateway.api_base_url}/print/cloudprnt"
  alert_topic_arn  = module.alerts.topic_arn
}
