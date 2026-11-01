# External client ports (CONTRACTS.md sections 12.1 and 13). Each feature
# module passes these to its functions as <X>_CLIENT. "simulator" is refused
# at runtime in prod (the application factory raises when ENVIRONMENT=prod),
# so prod keeps planning while the features are off.

variable "meta_client" {
  type        = string
  description = "Meta Graph client for meta-ads and social-posting (META_CLIENT): simulator or real."
  sensitive   = false
  default     = "simulator"

  validation {
    condition     = contains(["simulator", "real"], var.meta_client)
    error_message = "meta_client must be simulator or real."
  }
}

variable "google_business_client" {
  type        = string
  description = "Google Business Profile client for google-business (GOOGLE_BUSINESS_CLIENT): simulator or real."
  sensitive   = false
  default     = "simulator"

  validation {
    condition     = contains(["simulator", "real"], var.google_business_client)
    error_message = "google_business_client must be simulator or real."
  }
}

variable "fortnox_client" {
  type        = string
  description = "Fortnox client for accounting-sync (FORTNOX_CLIENT): simulator or real."
  sensitive   = false
  default     = "simulator"

  validation {
    condition     = contains(["simulator", "real"], var.fortnox_client)
    error_message = "fortnox_client must be simulator or real."
  }
}

variable "visma_client" {
  type        = string
  description = "Visma eAccounting client for accounting-sync (VISMA_CLIENT): simulator or real."
  sensitive   = false
  default     = "simulator"

  validation {
    condition     = contains(["simulator", "real"], var.visma_client)
    error_message = "visma_client must be simulator or real."
  }
}

variable "bedrock_client" {
  type        = string
  description = "Amazon Bedrock text model client for meta-ads copy and site-builder AI edits (BEDROCK_CLIENT): simulator or real."
  sensitive   = false
  default     = "simulator"

  validation {
    condition     = contains(["simulator", "real"], var.bedrock_client)
    error_message = "bedrock_client must be simulator or real."
  }
}

variable "bedrock_model_id" {
  type        = string
  description = "Bedrock model id used by the real text client (BEDROCK_MODEL_ID). Empty = none; the real client refuses an empty id. bedrock:InvokeModel is granted only on this model."
  sensitive   = false
  default     = ""
}
