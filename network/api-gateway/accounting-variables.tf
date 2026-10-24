variable "accounting_invoke_arn" {
  description = "Invoke ARN (live alias) of the accounting Lambda (Bokföring export)"
  type        = string
}

variable "accounting_function_name" {
  description = "Name of the accounting Lambda"
  type        = string
}
