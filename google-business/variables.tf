variable "environment" {
  description = "The environment to deploy to (dev or prod)"
  type        = string
  sensitive   = false
}

variable "region" {
  type = string
}

variable "ecr_repository_urls" {
  description = "ECR repository URL per function: google-business, google-business-jobs"
  type        = map(string)
}

variable "tenant_table_name" {
  type = string
}

variable "location_table_arn" {
  type        = string
  description = "Location table: the API lists a tenant's locations (Query on its own partition) for disconnect and the privacy hooks."
}

variable "location_table_name" {
  type = string
}

variable "location_id_index_name" {
  type = string
}

variable "reservation_table_name" {
  type = string
}

variable "reservation_table_arn" {
  type = string
}

variable "order_table_name" {
  type = string
}

variable "order_table_arn" {
  type = string
}

variable "consent_table_name" {
  type = string
}

variable "consent_table_arn" {
  type = string
}

variable "marketing_link_key_secret_arn" {
  description = "Marketing link HMAC key (signs the guest's withdraw link)"
  type        = string
}

variable "ses_identity_arn" {
  description = "SES identity of the no-reply sender"
  type        = string
}

variable "from_address" {
  description = "No-reply From address (mail.<domain>)"
  type        = string
}

variable "mail_outbox_bucket_name" {
  description = "Dev mail outbox bucket (\"\" = send through SES)"
  type        = string
}

variable "mail_outbox_bucket_arn" {
  description = "Dev mail outbox bucket ARN (\"\" = none)"
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

variable "google_business_client" {
  description = "GOOGLE_BUSINESS_CLIENT: simulator or real (root var.google_business_client)"
  type        = string

  validation {
    condition     = contains(["simulator", "real"], var.google_business_client)
    error_message = "google_business_client must be simulator or real."
  }

  # The release guard for prod: "real" there only once the owner releases it.
  validation {
    condition     = !(var.environment == "prod" && var.google_business_client == "real" && !var.google_business_prod_released)
    error_message = "google_business_client = \"real\" in prod needs google_business_prod_released = true (the owner's release)."
  }
}

variable "google_business_prod_released" {
  description = "Root var.google_business_prod_released: the owner's go for real Google calls in prod"
  type        = bool
  default     = false
}

variable "admin_app_url" {
  description = "Admin app base URL (OAuth redirect lands on Inställningar > Profil; /api is the link base)"
  type        = string
}

variable "notification_function_arn" {
  description = "notification live alias ARN (review SMS, CONTRACTS.md 9.4)"
  type        = string
}

variable "marketing_configuration_set_name" {
  description = "Marketing SES configuration set name: review emails report bounces and complaints to marketing-sync"
  type        = string
}

variable "marketing_configuration_set_arn" {
  description = "Marketing SES configuration set ARN (ses:SendRawEmail resource)"
  type        = string
}

variable "marketing_table_name" {
  description = "Marketing table: the MSG#<id> SES lookup row marketing-sync reads"
  type        = string
}

variable "marketing_table_arn" {
  description = "Marketing table ARN (PutItem of the MSG#<id> row only)"
  type        = string
}
