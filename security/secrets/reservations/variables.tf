variable "environment" {
  description = "The environment to deploy to (dev or prod)"
  type        = string
  sensitive   = false
}

variable "reader_role_names" {
  description = "Execution roles (stable key => role name) that may read the link signing key: the functions that build or verify guests' manage links"
  type        = map(string)
  sensitive   = false
}
