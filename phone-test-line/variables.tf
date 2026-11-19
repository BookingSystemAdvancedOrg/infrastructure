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
