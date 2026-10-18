variable "environment" {
  description = "The environment to deploy to (dev or prod)"
  type        = string
  sensitive   = false
}

variable "allowed_origins" {
  description = "Origins of the operator console (Booqy Console) - the only pages that upload here"
  type        = list(string)
  sensitive   = false
}
