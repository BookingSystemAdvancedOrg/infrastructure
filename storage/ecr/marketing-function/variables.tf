variable "environment" {
  description = "The environment to deploy to (dev or prod)"
  type        = string
}

variable "function" {
  description = "Function folder name in the application repo, e.g. marketing-send"
  type        = string
}
