variable "environment" {
  description = "The environment to deploy to (dev or prod)"
  type        = string
  sensitive   = false
}

variable "region" {
  type = string
}

variable "ecr_repository_urls" {
  description = "ECR repository URL per function: meta-ads, meta-ads-jobs"
  type        = map(string)
}

variable "tenant_table_name" {
  type = string
}

variable "tenant_table_arn" {
  type = string
}

variable "location_table_name" {
  type = string
}

variable "location_id_index_name" {
  type = string
}

variable "user_table_name" {
  type = string
}

variable "user_table_arn" {
  type = string
}

variable "user_tenant_index_name" {
  type = string
}

variable "menu_table_name" {
  type = string
}

variable "menu_table_arn" {
  type = string
}

variable "marketing_table_name" {
  type = string
}

variable "marketing_table_arn" {
  type = string
}

variable "menu_image_bucket_name" {
  type = string
}

variable "menu_image_bucket_arn" {
  type = string
}

variable "notification_function_arn" {
  description = "notification live alias ARN (80 % cap mail)"
  type        = string
}

variable "event_bus_name" {
  type = string
}

variable "event_bus_arn" {
  type = string
}

variable "alert_topic_arn" {
  type = string
}

variable "meta_client" {
  description = "META_CLIENT: simulator or real (root var.meta_client)"
  type        = string
}

variable "bedrock_client" {
  description = "BEDROCK_CLIENT: simulator or real (root var.bedrock_client)"
  type        = string
}

variable "bedrock_model_id" {
  description = "Bedrock model or inference profile id; empty = no Bedrock access granted"
  type        = string
}

variable "admin_app_url" {
  description = "Admin app base URL (the Meta login redirect lands on Marknadsföring > Annonser)"
  type        = string
}

variable "site_domain" {
  description = "Restaurant sites' parent domain (<slug>.<domain>) for ad links"
  type        = string
}

variable "platform_daily_spend_alarm_sek" {
  description = "Alarm when all restaurants together spend more than this per day on Meta ads (Booqy/MetaAds PlatformSpendSek)"
  type        = number
  default     = 5000
}
