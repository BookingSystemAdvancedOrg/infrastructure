# AI phone agent, the AWS-only test line (owner 2026-11-13, dev only): a real
# phone number that reaches Booqy's agent without the ElevenLabs/46elks
# accounts. Amazon Connect (Frankfurt: Connect has no Stockholm region) answers
# with Polly's Swedish neural voice Elin, a Lex V2 bot (sv_SE) turns speech
# into text, and a relay Lambda next to it hands every utterance to
# phone-agent-call:live in Stockholm, whose agent loop (Claude on Bedrock,
# Booqy's tools) answers. The Lex bot, its version and alias (with the code
# hook) and the Connect-Lex association are a CloudFormation stack: Terraform
# has no Lex V2 alias resource.
#
# IAM (approved by the owner 2026-11-13, all new, dev only):
#   1. aws_iam_role.lex: Lex's service role (Polly speech for the bot).
#   2. aws_lambda_permission.lex: the bot alias may invoke the relay.
#   3. aws_iam_role.relay: the relay may invoke phone-agent-call:live only, plus its own logs.
#   4. Connect's service-linked role, created by AWS with the instance.

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  prefix = "${var.environment}-"
  name   = "${local.prefix}phone-test-line"
}

# --- 3. the relay ------------------------------------------------------------------------

data "archive_file" "relay" {
  type        = "zip"
  output_path = "${path.module}/.build/relay.zip"
  source {
    filename = "index.py"
    content  = <<-PY
      import json, os
      import boto3

      _lambda = boto3.client("lambda", region_name=os.environ["TARGET_REGION"])


      def handler(event, context):
          """A Lex V2 code hook event in, the agent's Lex response out."""
          answer = _lambda.invoke(FunctionName=os.environ["TARGET"], InvocationType="RequestResponse",
                                  Payload=json.dumps({"lexV2": event}).encode("utf-8"))
          return json.loads(answer["Payload"].read() or b"{}")
    PY
  }
}

resource "aws_iam_role" "relay" {
  name = "${local.name}-relay-role"
  assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Effect = "Allow", Principal = { Service = "lambda.amazonaws.com" }, Action = "sts:AssumeRole" }]
  })
  tags = { Environment = var.environment }
}

resource "aws_iam_role_policy" "relay" {
  name = "relay"
  role = aws_iam_role.relay.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Sid = "InvokeTheAgent", Effect = "Allow", Action = ["lambda:InvokeFunction"], Resource = var.call_alias_arn },
      {
        Sid      = "OwnLogs"
        Effect   = "Allow"
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "arn:aws:logs:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/${local.name}-relay:*"
      },
    ]
  })
}

resource "aws_cloudwatch_log_group" "relay" {
  name              = "/aws/lambda/${local.name}-relay"
  retention_in_days = 14
}

resource "aws_lambda_function" "relay" {
  function_name    = "${local.name}-relay"
  role             = aws_iam_role.relay.arn
  runtime          = "python3.13"
  handler          = "index.handler"
  filename         = data.archive_file.relay.output_path
  source_code_hash = data.archive_file.relay.output_base64sha256
  timeout          = 30
  memory_size      = 256
  environment {
    variables = {
      TARGET        = var.call_alias_arn
      TARGET_REGION = split(":", var.call_alias_arn)[3]
    }
  }
  depends_on = [aws_cloudwatch_log_group.relay]
  tags       = { Environment = var.environment }
}

# --- 1. Lex's service role ---------------------------------------------------------------

resource "aws_iam_role" "lex" {
  name = "${local.name}-lex-role"
  assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Effect = "Allow", Principal = { Service = "lexv2.amazonaws.com" }, Action = "sts:AssumeRole" }]
  })
  tags = { Environment = var.environment }
}

resource "aws_iam_role_policy" "lex" {
  name = "polly"
  role = aws_iam_role.lex.id
  policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Sid = "Speech", Effect = "Allow", Action = ["polly:SynthesizeSpeech"], Resource = "*" }]
  })
}

# --- Connect (4. its service-linked role comes with the instance) ------------------------

resource "aws_connect_instance" "this" {
  identity_management_type = "CONNECT_MANAGED"
  instance_alias           = "booqy-${var.environment}-phone-test-${data.aws_caller_identity.current.account_id}"
  inbound_calls_enabled    = true
  outbound_calls_enabled   = false
  contact_lens_enabled     = false
  tags                     = { Environment = var.environment }
}

# --- the Lex bot, version, alias with the relay as code hook, and the Connect association -

resource "aws_cloudformation_stack" "lex" {
  name = "${local.name}-lex"
  parameters = {
    BotName     = "${local.name}-bot"
    LexRoleArn  = aws_iam_role.lex.arn
    RelayArn    = aws_lambda_function.relay.arn
    InstanceArn = aws_connect_instance.this.arn
  }
  template_body = file("${path.module}/lex.yaml")
  tags          = { Environment = var.environment }
}

# --- 2. the bot alias may invoke the relay -----------------------------------------------

resource "aws_lambda_permission" "lex" {
  statement_id  = "lex-bot-alias"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.relay.function_name
  principal     = "lexv2.amazonaws.com"
  source_arn    = aws_cloudformation_stack.lex.outputs["AliasArn"]
}

# --- the call flow and the number --------------------------------------------------------

resource "aws_connect_contact_flow" "this" {
  instance_id = aws_connect_instance.this.id
  name        = "Booqy telefonassistent (test)"
  type        = "CONTACT_FLOW"
  content = templatefile("${path.module}/flow.json.tftpl", {
    alias_arn = aws_cloudformation_stack.lex.outputs["AliasArn"]
    greeting  = var.greeting
  })
  tags = { Environment = var.environment }
}

resource "aws_connect_phone_number" "this" {
  target_arn   = aws_connect_instance.this.arn
  country_code = var.country_code
  type         = "DID"
  tags         = { Environment = var.environment }
}

resource "aws_connect_phone_number_contact_flow_association" "this" {
  phone_number_id = aws_connect_phone_number.this.id
  instance_id     = aws_connect_instance.this.id
  contact_flow_id = aws_connect_contact_flow.this.contact_flow_id
}
