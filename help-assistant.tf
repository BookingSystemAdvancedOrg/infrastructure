# In-app help assistant (help-assistant/): the help chatbot in Booqy Admin.
module "help_assistant" {
  source                   = "./help-assistant"
  environment              = var.env
  region                   = var.aws_region
  ecr_repository_url       = module.help_assistant_ecr.repository_url
  tenant_table_name        = module.tenant.table_name
  location_table_name      = module.location.table_name
  location_id_index_name   = module.location.location_id_index_name
  request_guard_table_name = module.request_guard.table_name
  request_guard_table_arn  = module.request_guard.table_arn
  alert_topic_arn          = module.alerts.topic_arn
  enabled                  = var.help_assistant_enabled
  monthly_answers          = var.help_assistant_monthly_answers
  bedrock_client           = var.bedrock_client
  bedrock_model_id         = var.bedrock_model_id
}

variable "help_assistant_enabled" {
  type        = bool
  description = "Turns the in-app help assistant on (HELP_ASSISTANT_ENABLED). Off by default. The PLATFORM#HELP_ASSISTANT/SETTINGS row on the tenant table ({enabled: false}) switches it off at runtime without a deploy."
  sensitive   = false
  default     = false
}

variable "help_assistant_monthly_answers" {
  type = object({
    per_tenant = number
    total      = number
  })
  description = "Cost cap: Bedrock answers per tenant and for the whole platform per 30-day window. Past the cap the assistant answers from the help texts only (no model call)."
  sensitive   = false
  default     = { per_tenant = 300, total = 10000 }

  validation {
    condition     = var.help_assistant_monthly_answers.per_tenant >= 0 && var.help_assistant_monthly_answers.total >= var.help_assistant_monthly_answers.per_tenant
    error_message = "help_assistant_monthly_answers: per_tenant >= 0 and total >= per_tenant."
  }
}
