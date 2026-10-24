variable "kassa_invoke_arn" {
  description = "Invoke ARN (live alias) of the kassa Lambda (the till)"
  type        = string
}

variable "kassa_function_name" {
  description = "Name of the kassa Lambda"
  type        = string
}
