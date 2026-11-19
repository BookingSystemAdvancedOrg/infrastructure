# AI phone agent, the AWS-only test line (owner 2026-11-13, dev only): a real
# phone number that reaches Booqy's agent without the ElevenLabs/46elks
# accounts. Amazon Connect (Frankfurt: Connect has no Stockholm region) answers
# with Polly's Swedish neural voice Elin, a Lex V2 bot (sv_SE, plus one locale
# per call language in languages.json, owner 2026-11-18) turns speech into
# text, and a relay Lambda next to it hands every utterance to
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
#   5. aws_lambda_permission.connect (2026-11-19): the Connect instance may invoke the
#      relay (the flow fetches the greeting with the restaurant's name from Booqy).

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  prefix = "${var.environment}-"
  name   = "${local.prefix}phone-test-line"

  # Call languages (owner 2026-11-18): our code -> Lex locale, Connect
  # language code, Polly voice and engine. languages.json is a copy of
  # application/shared/features/phone_agent/aws_languages.json (same content;
  # change both together). The agent switches language by closing the Lex
  # turn with next=switch; the flow then sets the language and voice it names
  # and starts this bot again in that locale.
  phone_languages = jsondecode(file("${path.module}/languages.json")).languages
  # Sample utterances and filler lines per locale, in that language.
  lex_texts = jsondecode(file("${path.module}/lex-texts.json")).texts
  # A new BotVersion logical id whenever a locale, a filler or the template changes.
  lex_version_id = "BotVersion${substr(sha256(join("\n", [
    file("${path.module}/languages.json"),
    file("${path.module}/lex-texts.json"),
    file("${path.module}/lex.yaml.tftpl"),
  ])), 0, 12)}"
  # Compact JSON: CloudFormation's template_body takes at most 51,200 bytes.
  lex_template = jsonencode(yamldecode(templatefile("${path.module}/lex.yaml.tftpl", {
    languages  = local.phone_languages
    texts      = local.lex_texts
    version_id = local.lex_version_id
  })))
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
          """A Lex V2 code hook event in, the agent's Lex response out; the
          flow's InvokeLambdaFunction (Name ContactFlowEvent) in, the greeting
          from the restaurant's data out ({"ok", "greeting"})."""
          if event.get("Name") == "ContactFlowEvent":
              params = (event.get("Details") or {}).get("Parameters") or {}
              payload = {"connectGreeting": {"dialedNumber": params.get("dialedNumber")}}
          else:
              payload = {"lexV2": event}
          answer = _lambda.invoke(FunctionName=os.environ["TARGET"], InvocationType="RequestResponse",
                                  Payload=json.dumps(payload).encode("utf-8"))
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
  template_body = local.lex_template
  tags          = { Environment = var.environment }

  lifecycle {
    precondition {
      condition     = alltrue([for code in keys(local.phone_languages) : contains(keys(local.lex_texts), code)])
      error_message = "Every language in languages.json needs utterances and filler lines in lex-texts.json."
    }
    precondition {
      # Bytes, not characters (base64 of the UTF-8 text is 4/3 of its size).
      condition     = length(base64encode(local.lex_template)) * 3 / 4 <= 51200
      error_message = "The rendered Lex template is over CloudFormation's 51,200 byte template_body limit: drop filler variations or utterances, or move the template to S3 (template_url)."
    }
  }
}

# --- 2. the bot alias may invoke the relay -----------------------------------------------

resource "aws_lambda_permission" "lex" {
  statement_id  = "lex-bot-alias"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.relay.function_name
  principal     = "lexv2.amazonaws.com"
  source_arn    = aws_cloudformation_stack.lex.outputs["AliasArn"]
}

# --- 5. the flow may invoke the relay for the greeting ----------------------------------
# The greeting names the restaurant from its own data (owner 2026-11-19: never set by hand):
# the flow asks Booqy through the relay before the bot starts; on any error it plays
# var.greeting, which names no restaurant.

resource "aws_lambda_permission" "connect" {
  statement_id  = "connect-instance"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.relay.function_name
  principal     = "connect.amazonaws.com"
  source_arn    = aws_connect_instance.this.arn
}

resource "aws_connect_lambda_function_association" "relay" {
  instance_id  = aws_connect_instance.this.id
  function_arn = aws_lambda_function.relay.arn
  depends_on   = [aws_lambda_permission.connect]
}

# --- the call flow and the number --------------------------------------------------------

resource "aws_connect_contact_flow" "this" {
  instance_id = aws_connect_instance.this.id
  name        = "Booqy telefonassistent (test)"
  type        = "CONTACT_FLOW"
  content = templatefile("${path.module}/flow.json.tftpl", {
    alias_arn = aws_cloudformation_stack.lex.outputs["AliasArn"]
    relay_arn = aws_connect_lambda_function_association.relay.function_arn
    greeting  = var.greeting
    # After a failed language switch: back to Swedish and on with the call.
    resume_sv = "Förlåt, vi fortsätter på svenska. Vad kan jag hjälpa dig med?"
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
