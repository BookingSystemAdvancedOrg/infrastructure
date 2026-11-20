# Dev A2A test (owner 2026-11-20, dev only, off unless a2a_dev_test_enabled): Amazon Connect hands a
# call on the phone test line's instance to the Booqy voice gateway as an external A2A agent with
# audio streaming (application/services/voice-gateway/CONNECT-A2A.md). This file: the API key, the
# Connect AI objects, the security profile wiring and a separate test flow. gateway.tf: the wss
# endpoint (Fargate behind an ALB). Everything here is eu-central-1, next to the Connect instance.
#
# IAM call-out (all NEW roles and resource policies, dev only; no existing role, no OIDC or deploy role):
#   1. aws_kms_key.a2a policy: connect.amazonaws.com may kms:Decrypt through Secrets Manager.
#   2. aws_secretsmanager_secret_policy.a2a: the Connect instance may read the API key secret.
#   3. aws_iam_role.lex: the A2A bot's service role (Connect AI agent session calls, Nova Sonic);
#      trusts lexv2.amazonaws.com and lexv2.aws.internal (this account's bot aliases only).
#   4. gateway.tf: the task execution role and the task role.
#
# Not in Terraform or CloudFormation (run by CI through the AWS CLI, terraform_data.wiring):
# AllowedAIAgents on the security profile, AssociateSecurityProfiles for the AI agent and the
# assistant's default self-service orchestration agent.

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  prefix   = "${var.environment}-"
  name     = "${local.prefix}voice-gateway-a2a"
  account  = data.aws_caller_identity.current.account_id
  region   = data.aws_region.current.region
  hostname = "voice-a2a.${var.platform_domain}"

  # AIAgentVersionId is a string like "<agent id>:<n>"; the trailing number is the version.
  agent_version_parts = split(":", aws_cloudformation_stack.connect_ai.outputs["AgentVersionId"])
  agent_version       = element(local.agent_version_parts, length(local.agent_version_parts) - 1)

  # A new BotVersion logical id whenever the template or the speech model changes.
  bot_version_id = "BotVersion${substr(sha256(join("\n", [
    file("${path.module}/connect-ai.yaml.tftpl"),
    var.speech_model_arn,
  ])), 0, 12)}"
}

# --- the API key Connect sends and the gateway checks ------------------------------------

# 1. Connect decrypts the secret through Secrets Manager (the aws/secretsmanager key does not work).
resource "aws_kms_key" "a2a" {
  description             = "${local.name}: the A2A API key secret (Connect reads it)"
  deletion_window_in_days = 7
  enable_key_rotation     = true
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AccountAdmin"
        Effect    = "Allow"
        Principal = { AWS = "arn:aws:iam::${local.account}:root" }
        Action    = "kms:*"
        Resource  = "*"
      },
      {
        Sid       = "AllowConnectToDecryptSecret"
        Effect    = "Allow"
        Principal = { Service = "connect.amazonaws.com" }
        Action    = "kms:Decrypt"
        Resource  = "*"
        Condition = { StringEquals = { "kms:ViaService" = "secretsmanager.${local.region}.amazonaws.com" } }
      },
    ]
  })
  tags = { Environment = var.environment }
}

resource "aws_kms_alias" "a2a" {
  name          = "alias/${local.name}"
  target_key_id = aws_kms_key.a2a.key_id
}

resource "aws_secretsmanager_secret" "a2a" {
  name        = "${local.name}-api-key"
  description = "API key Connect sends to the voice gateway (A2A, Authorization: Bearer)"
  kms_key_id  = aws_kms_key.a2a.arn
  # Dev test: gone at once on destroy, so the next test session can create it again.
  recovery_window_in_days = 0
  tags                    = { Environment = var.environment }
}

# Generated here, written write-only: never in state, the repo or the plan. Bump the version to rotate.
ephemeral "aws_secretsmanager_random_password" "a2a" {
  password_length     = 64
  exclude_punctuation = true
}

resource "aws_secretsmanager_secret_version" "a2a" {
  secret_id                = aws_secretsmanager_secret.a2a.id
  secret_string_wo         = ephemeral.aws_secretsmanager_random_password.a2a.random_password
  secret_string_wo_version = 1
}

# 2. Only this Connect instance may read it.
resource "aws_secretsmanager_secret_policy" "a2a" {
  secret_arn = aws_secretsmanager_secret.a2a.arn
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "ConnectReadsTheKey"
      Effect    = "Allow"
      Principal = { Service = "connect.amazonaws.com" }
      Action    = "secretsmanager:GetSecretValue"
      Resource  = "*"
      Condition = {
        StringEquals = {
          "aws:SourceAccount" = local.account
          "aws:SourceArn"     = var.instance_arn
        }
      }
    }]
  })
}

# --- 3. the A2A bot's service role -------------------------------------------------------

resource "aws_iam_role" "lex" {
  name = "${local.name}-lex-role"
  # lexv2.aws.internal: the trust the AMAZON.QInConnectIntent page asks for on a custom bot role
  # (Lex assumes it for the Connect AI agent session), limited to this account's bot aliases.
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { Service = "lexv2.amazonaws.com" }
        Action    = "sts:AssumeRole"
        Condition = { StringEquals = { "aws:SourceAccount" = local.account } }
      },
      {
        Sid       = "LexV2InternalTrustPolicy"
        Effect    = "Allow"
        Principal = { Service = "lexv2.aws.internal" }
        Action    = "sts:AssumeRole"
        Condition = {
          StringEquals = { "aws:SourceAccount" = local.account }
          ArnLike      = { "aws:SourceArn" = "arn:aws:lex:${local.region}:${local.account}:bot-alias/*" }
        }
      },
    ]
  })
  tags = { Environment = var.environment }
}

# Attached before the stack, so the bot builds with it in place. Assistants and sessions in this
# account and Region only (the stack makes the one assistant there is).
resource "aws_iam_role_policy" "lex" {
  name = "a2a"
  role = aws_iam_role.lex.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # AMAZON.QInConnectIntent: a Connect AI agent session on the assistant.
        Sid    = "ConnectAIAgentSession"
        Effect = "Allow"
        Action = ["wisdom:CreateSession", "wisdom:GetSession", "wisdom:GetAssistant", "wisdom:SendMessage", "wisdom:GetNextMessage"]
        Resource = [
          "arn:aws:wisdom:${local.region}:${local.account}:assistant/*",
          "arn:aws:wisdom:${local.region}:${local.account}:session/*",
        ]
      },
      {
        # The locale's unified speech model (placeholder: with audio streaming the gateway speaks).
        Sid      = "SpeechModel"
        Effect   = "Allow"
        Action   = ["bedrock:InvokeModel", "bedrock:InvokeModelWithBidirectionalStream"]
        Resource = var.speech_model_arn
      },
    ]
  })
}

# --- Connect AI objects (CloudFormation: no Terraform resources for them) ----------------

resource "aws_cloudformation_stack" "connect_ai" {
  name = "${local.name}-connect-ai"
  parameters = {
    Name           = local.name
    InstanceArn    = var.instance_arn
    AccessUrl      = "wss://${local.hostname}"
    SecretArn      = aws_secretsmanager_secret.a2a.arn
    LexRoleArn     = aws_iam_role.lex.arn
    SpeechModelArn = var.speech_model_arn
    Environment    = var.environment
  }
  template_body = templatefile("${path.module}/connect-ai.yaml.tftpl", { version_id = local.bot_version_id })
  tags          = { Environment = var.environment }

  timeouts {
    create = "30m"
    update = "30m"
    delete = "30m"
  }

  # The application is created with the key in place and Connect allowed to read it.
  depends_on = [
    aws_secretsmanager_secret_version.a2a,
    aws_secretsmanager_secret_policy.a2a,
    aws_iam_role_policy.lex,
  ]
}

# --- the AI agent's security profile ----------------------------------------------------

# BasicAgentAccess is "Access Contact Control Panel": without it Connect sends no contactContext,
# the gateway gets no dialed number and cannot find the restaurant.
resource "aws_connect_security_profile" "a2a" {
  instance_id = var.instance_id
  name        = local.name
  description = "Booqy voice gateway AI agent (dev A2A test)"
  permissions = ["BasicAgentAccess"]
  tags        = { Environment = var.environment }
}

# No CloudFormation or Terraform for these three (2026-11-20). Idempotent; the destroy step undoes
# them before the stack and the profile go. Needs an AWS CLI that knows --allowed-ai-agents.
resource "terraform_data" "wiring" {
  input = {
    region      = local.region
    instance_id = var.instance_id
    profile_id  = aws_connect_security_profile.a2a.security_profile_id
    app_arn     = aws_cloudformation_stack.connect_ai.outputs["ApplicationArn"]
    assistant   = aws_cloudformation_stack.connect_ai.outputs["AssistantId"]
    agent_id    = aws_cloudformation_stack.connect_ai.outputs["AgentId"]
    agent_arn   = replace(aws_cloudformation_stack.connect_ai.outputs["AgentArn"], ":$LATEST", "")
    version     = local.agent_version
    use_case    = var.orchestrator_use_case
  }
  triggers_replace = [
    aws_connect_security_profile.a2a.security_profile_id,
    aws_cloudformation_stack.connect_ai.outputs["ApplicationArn"],
    aws_cloudformation_stack.connect_ai.outputs["AgentArn"],
    local.agent_version,
    var.orchestrator_use_case,
  ]

  provisioner "local-exec" {
    interpreter = ["bash", "-c"]
    environment = {
      R        = self.input.region
      INSTANCE = self.input.instance_id
      SP       = self.input.profile_id
      APP_ARN  = self.input.app_arn
      ASST     = self.input.assistant
      AGENT_ID = self.input.agent_id
      AGENT    = self.input.agent_arn
      VERSION  = self.input.version
      USE_CASE = self.input.use_case
    }
    command = <<-EOT
      set -euo pipefail
      if ! aws connect update-security-profile --generate-cli-skeleton input | grep -q AllowedAIAgents; then
        echo "::error::this AWS CLI ($(aws --version)) has no update-security-profile --allowed-ai-agents; the runner needs a newer AWS CLI v2"
        exit 1
      fi
      # Already associated counts as done.
      tolerate() { local out; if ! out=$("$@" 2>&1); then echo "$out" | grep -qiE "already|duplicate|conflict" || { echo "$out" >&2; return 1; }; fi; }
      aws connect update-security-profile --region "$R" --instance-id "$INSTANCE" --security-profile-id "$SP" \
        --allowed-ai-agents "[{\"Arn\":\"$APP_ARN\",\"Type\":\"THIRD_PARTY\"}]"
      for arn in "$AGENT" "$AGENT:$VERSION"; do
        tolerate aws connect associate-security-profiles --region "$R" --instance-id "$INSTANCE" \
          --security-profiles "Id=$SP" --entity-type AI_AGENT --entity-arn "$arn"
      done
      aws qconnect update-assistant-ai-agent --region "$R" --assistant-id "$ASST" --ai-agent-type ORCHESTRATION \
        --orchestrator-use-case "$USE_CASE" --configuration "aiAgentId=$AGENT_ID:$VERSION" --output text --query assistant.assistantId
    EOT
  }

  provisioner "local-exec" {
    when        = destroy
    interpreter = ["bash", "-c"]
    environment = {
      R        = self.input.region
      INSTANCE = self.input.instance_id
      SP       = self.input.profile_id
      ASST     = self.input.assistant
      AGENT    = self.input.agent_arn
      VERSION  = self.input.version
      USE_CASE = self.input.use_case
    }
    command = <<-EOT
      set -uo pipefail
      aws qconnect remove-assistant-ai-agent --region "$R" --assistant-id "$ASST" --ai-agent-type ORCHESTRATION \
        --orchestrator-use-case "$USE_CASE" || true
      for arn in "$AGENT:$VERSION" "$AGENT"; do
        aws connect disassociate-security-profiles --region "$R" --instance-id "$INSTANCE" \
          --security-profiles "Id=$SP" --entity-type AI_AGENT --entity-arn "$arn" || true
      done
      aws connect update-security-profile --region "$R" --instance-id "$INSTANCE" --security-profile-id "$SP" \
        --allowed-ai-agents "[]" || true
    EOT
  }
}

# --- the separate test flow --------------------------------------------------------------

resource "aws_connect_contact_flow" "a2a" {
  instance_id = var.instance_id
  name        = "Booqy röstgateway A2A (test)"
  description = "Dev A2A test: the call goes to the Booqy voice gateway; on error to the Stage 1 flow"
  type        = "CONTACT_FLOW"
  content = templatefile("${path.module}/flow.json.tftpl", {
    alias_arn         = aws_cloudformation_stack.connect_ai.outputs["AliasArn"]
    assistant_arn     = aws_cloudformation_stack.connect_ai.outputs["AssistantArn"]
    fallback_flow_arn = var.fallback_flow_arn
    escalate_text     = "Här skulle samtalet kopplas till restaurangen. Det här är en testlinje, så samtalet avslutas nu."
  })
  tags = { Environment = var.environment }

  # The AI agent must be wired before the flow can hand a call to it.
  depends_on = [terraform_data.wiring]
}
