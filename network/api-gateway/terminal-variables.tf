variable "terminal_payments_invoke_arn" {
  description = "Invoke ARN (live alias) of the terminal-payments Lambda (card payments at the till)"
  type        = string
}

variable "terminal_payments_function_name" {
  description = "Name of the terminal-payments Lambda"
  type        = string
}
