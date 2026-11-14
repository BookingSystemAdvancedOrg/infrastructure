variable "environment" {
  type = string
}

variable "call_alias_arn" {
  description = "phone-agent-call:live in eu-north-1, the only function the relay may invoke"
  type        = string
}

variable "greeting" {
  description = "What the caller hears first: the art. 50 disclosure and the question (same text as Booqy's greeting)"
  type        = string
}

variable "country_code" {
  description = "Country of the test number (DID); SE, or DE when Swedish numbers need paperwork"
  type        = string
  default     = "SE"
}
