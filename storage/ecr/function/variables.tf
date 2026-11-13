variable "environment" {
  description = "The environment to deploy to (dev or prod)"
  type        = string
}

variable "function" {
  description = "Function folder name in the application repo, for example kassa"
  type        = string
}

variable "force_delete" {
  description = "Delete the repository even when it still holds images; set for one release before the module is removed"
  type        = bool
  default     = false
}
