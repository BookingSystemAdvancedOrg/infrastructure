variable "environment" {
  description = "The environment to deploy to (dev or prod)"
  type        = string
}

variable "function" {
  description = "Function folder name in the application repo, terminal-payments"
  type        = string
}
