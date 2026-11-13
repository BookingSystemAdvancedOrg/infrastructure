variable "environment" {
  description = "The environment to deploy to (dev or prod)"
  type        = string
  sensitive   = false
}

variable "allowed_origins" {
  description = "Origins of the admin app and Booqy Console - the pages that upload backdrop images here"
  type        = list(string)
  sensitive   = false
}
