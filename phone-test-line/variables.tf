variable "environment" {
  type = string
}

variable "call_alias_arn" {
  description = "phone-agent-call:live in eu-north-1, the only function the relay may invoke"
  type        = string
}

variable "greeting" {
  description = "The fallback first sentence when Booqy's greeting (with the restaurant's name) cannot be fetched: the disclosure without a name, and the question"
  type        = string
}

variable "country_code" {
  description = "Country of the test number (DID); SE, or DE when Swedish numbers need paperwork"
  type        = string
  default     = "SE"
}

variable "flow_logs" {
  description = "Connect flow logs to CloudWatch (14 days) for a debug session. Off by default: the logs record what the flow sends to and receives from Lex, which includes the caller's number and the spoken reply text"
  type        = bool
  default     = false
}

variable "contact_flow_id_override" {
  description = "Another flow on this instance for the number (the dev A2A test flow); null = the Stage 1 flow"
  type        = string
  default     = null
}
