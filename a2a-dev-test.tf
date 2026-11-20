# Dev A2A test (owner 2026-11-20, dev only): Amazon Connect hands a call on the phone test line to
# the Booqy voice gateway as an external A2A agent with audio streaming (a2a-dev-test/, plan:
# application/services/voice-gateway/CONNECT-A2A.md). Off unless a2a_dev_test_enabled; while it is
# on, Fargate and the ALB cost about $0.095 per hour. The test number stays on the Stage 1 flow
# until a2a_dev_test_live. Session: enabled -> push the image -> live -> test -> live false ->
# enabled false (destroys everything here).

variable "a2a_dev_test_enabled" {
  type        = bool
  description = "The dev A2A test: Connect AI agent, test flow and the voice gateway on Fargate (eu-central-1). Dev only, needs the phone test line."
  sensitive   = false
  default     = false

  validation {
    condition     = !var.a2a_dev_test_enabled || (var.env == "dev" && var.phone_test_line_enabled && var.platform_domain != "" && var.platform_domain_zone_id != "")
    error_message = "a2a_dev_test_enabled is for dev only and needs phone_test_line_enabled, platform_domain and platform_domain_zone_id."
  }
}

variable "a2a_dev_test_live" {
  type        = bool
  description = "Moves the test line's number to the A2A test flow (false: the number stays on the Stage 1 flow)."
  sensitive   = false
  default     = false

  validation {
    condition     = !var.a2a_dev_test_live || var.a2a_dev_test_enabled
    error_message = "a2a_dev_test_live needs a2a_dev_test_enabled."
  }
}

variable "a2a_dev_test_gateway_count" {
  type        = number
  description = "Running voice gateway tasks in the A2A test (0 stops Fargate, keeps the rest)."
  sensitive   = false
  default     = 1
}

variable "a2a_dev_test_image_tag" {
  type        = string
  description = "Voice gateway image tag in the A2A test's ECR repository."
  sensitive   = false
  default     = "latest"
}

variable "a2a_dev_test_speech_model_arn" {
  type        = string
  description = "Bedrock model of the A2A bot's Nova Sonic placeholder locale. Bedrock lists no Nova Sonic in eu-central-1 (2026-11-20): if Lex refuses this ARN, ask AWS for the one Connect uses in Frankfurt."
  sensitive   = false
  default     = "arn:aws:bedrock:eu-central-1::foundation-model/amazon.nova-2-sonic-v1:0"
}

variable "a2a_dev_test_orchestrator_use_case" {
  type        = string
  description = "qconnect UpdateAssistantAIAgent --orchestrator-use-case that makes the agent the assistant's self-service default (confirm on the first apply)."
  sensitive   = false
  default     = "Connect.SelfService"
}

module "a2a_dev_test" {
  count  = var.a2a_dev_test_enabled ? 1 : 0
  source = "./a2a-dev-test"
  providers = {
    aws     = aws.eu_central_1
    aws.ecr = aws
  }
  environment               = var.env
  instance_id               = module.phone_test_line[0].instance_id
  instance_arn              = module.phone_test_line[0].instance_arn
  fallback_flow_arn         = module.phone_test_line[0].contact_flow_arn
  platform_domain           = var.platform_domain
  platform_domain_zone_id   = var.platform_domain_zone_id
  gateway_environment       = module.phone_agent.gateway_access.environment
  gateway_statements        = module.phone_agent.gateway_access.statements
  agent_region              = var.aws_region
  tenant_context_policy_arn = module.tenant_context_policy.policy_arn
  speech_model_arn          = var.a2a_dev_test_speech_model_arn
  orchestrator_use_case     = var.a2a_dev_test_orchestrator_use_case
  gateway_count             = var.a2a_dev_test_gateway_count
  image_tag                 = var.a2a_dev_test_image_tag
}

output "a2a_dev_test" {
  description = "Dev A2A test: the wss endpoint, where to push the gateway image, the API key secret and the AI agent"
  value = try({
    gateway_url        = module.a2a_dev_test[0].gateway_url
    ecr_repository_url = module.a2a_dev_test[0].ecr_repository_url
    api_key_secret_arn = module.a2a_dev_test[0].api_key_secret_arn
    agent_arn          = module.a2a_dev_test[0].agent_arn
  }, null)
}
