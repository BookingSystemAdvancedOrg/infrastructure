variable "environment" {
  type = string
}

variable "instance_id" {
  description = "The phone test line's Connect instance (id)"
  type        = string
}

variable "instance_arn" {
  description = "The phone test line's Connect instance (ARN)"
  type        = string
}

variable "fallback_flow_arn" {
  description = "The phone test line's Stage 1 flow: the A2A flow's Error branch transfers there"
  type        = string
}

variable "platform_domain" {
  description = "The environment's platform domain (dev.booqy.se); the gateway gets voice-a2a.<platform_domain>"
  type        = string
}

variable "platform_domain_zone_id" {
  description = "Route 53 hosted zone of platform_domain"
  type        = string
}

variable "gateway_environment" {
  description = "Environment of the gateway container: the phone-agent-call Lambda's (the gateway runs its agent loop)"
  type        = map(string)
}

variable "gateway_statements" {
  description = "IAM statements of the gateway task role for the phone agent: phone-agent-call's, without its provider and endpoint secrets"
  type        = any
}

variable "agent_region" {
  description = "Region of the phone agent's tables, tool Lambdas and Bedrock model (eu-north-1): the gateway's default AWS region"
  type        = string
}

variable "tenant_context_policy_arn" {
  description = "The shared tenant-context read policy (tenant table, locationId index), as on phone-agent-call"
  type        = string
}

variable "speech_model_arn" {
  description = "Bedrock model of the Lex locale's unified speech settings (Nova Sonic speech to speech; a placeholder, the gateway does the speech)"
  type        = string
}

variable "orchestrator_use_case" {
  description = "qconnect UpdateAssistantAIAgent --orchestrator-use-case for the self-service default agent (confirm on the first apply)"
  type        = string
}

variable "gateway_count" {
  description = "Running gateway tasks (0 stops Fargate while keeping everything else)"
  type        = number
}

variable "image_tag" {
  description = "Tag of the voice gateway image in this module's ECR repository"
  type        = string
}
