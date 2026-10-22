variable "print_jobs_invoke_arn" {
  description = "Invoke ARN (live alias) of the print-jobs Lambda (admin printing API)"
  type        = string
  sensitive   = false
}

variable "print_jobs_function_name" {
  description = "Name of the print-jobs Lambda"
  type        = string
  sensitive   = false
}

variable "print_device_invoke_arn" {
  description = "Invoke ARN (live alias) of the print-device Lambda (CloudPRNT printers)"
  type        = string
  sensitive   = false
}

variable "print_device_function_name" {
  description = "Name of the print-device Lambda"
  type        = string
  sensitive   = false
}

variable "print_device_throttle_rate_limit" {
  description = "Steady-state requests per second for EACH printer route, all restaurants' printers together (one printer polls about every 5 s, 0.2 rps). Wrong secrets are limited per IP in the handler"
  type        = number
  sensitive   = false
  default     = 50
}

variable "print_device_throttle_burst_limit" {
  description = "Burst (requests) for each printer route"
  type        = number
  sensitive   = false
  default     = 100
}
