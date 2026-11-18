# Dev twins (booqy-console docs/DEV-TWINS.md; rules: BooqyCustomers/site-template
# docs/DATA-RULES.md). Every real customer has a twin in dev; copying goes
# prod -> dev only.
#
# Prod: when a restaurant finishes its Kom igång setup (Tenant.SetupCompleted,
# application functions/tenant-setup), site-repo is told to nudge dev
# ({action: twinContent}); dev then reads the restaurant's PUBLIC content
# (menu, hours, layout, photos) from prod's public API itself. Only the slug
# and tenant id cross, over the existing booqy-sites-prod-link path.

locals {
  twin_content_rule = var.env == "prod" && var.site_link_dev_account_id != "" && var.github_app_sites_secret_name != ""
}

resource "aws_cloudwatch_event_rule" "twin_content" {
  count          = local.twin_content_rule ? 1 : 0
  name           = "${var.env}-twin-content"
  description    = "A restaurant finished its setup: its dev twin copies the public content (site-repo twinContent)"
  event_bus_name = module.events.bus_name
  event_pattern = jsonencode({
    source        = ["booqy.tenant-setup"]
    "detail-type" = ["Tenant.SetupCompleted"]
  })
}

resource "aws_cloudwatch_event_target" "twin_content" {
  count          = local.twin_content_rule ? 1 : 0
  rule           = aws_cloudwatch_event_rule.twin_content[0].name
  event_bus_name = module.events.bus_name
  arn            = module.sites.alias_arn
  input_transformer {
    input_paths    = { tenantId = "$.detail.tenantId" }
    input_template = "{\"action\": \"twinContent\", \"tenantId\": <tenantId>}"
  }
  retry_policy {
    maximum_retry_attempts       = 3
    maximum_event_age_in_seconds = 3600
  }
}

resource "aws_lambda_permission" "twin_content" {
  count         = local.twin_content_rule ? 1 : 0
  statement_id  = "AllowTwinContentRule"
  action        = "lambda:InvokeFunction"
  function_name = module.sites.function_name
  qualifier     = module.sites.alias_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.twin_content[0].arn
}

variable "dev_twin_prod_api_url" {
  description = "Dev only: prod's PUBLIC API base URL. Twins read the real restaurant's public content (site-config, menu, active layout) there, and a new dev test customer may not take a slug a prod customer uses. \"\" = no copy, no slug check"
  type        = string
  default     = ""
}

variable "dev_twin_prod_image_url" {
  description = "Dev only: prod's public menu image base URL (CloudFront), for copying dish photos to the twin"
  type        = string
  default     = ""
}

variable "dev_twin_prod_domain" {
  description = "Dev only: prod's platform domain; a prod restaurant's slug address is <slug>.<this>"
  type        = string
  default     = "booqy.se"
}
