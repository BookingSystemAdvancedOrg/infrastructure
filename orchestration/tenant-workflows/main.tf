# The control plane's provisioning workflows. Adding a customer, attaching
# their domain or offboarding them is a Step Functions execution - never a
# Terraform change, never a code deploy.
#
#   tenant-onboarding     first owner (Cognito) -> Stripe connected account
#                         + VAT rates (Stripe HTTP tasks) -> <slug> subdomain
#                         (CloudFront distribution tenant) -> active
#   tenant-domain-attach  customer's own domain: claim it, distribution
#                         tenant with a CloudFront-managed certificate, poll
#                         until issued
#   tenant-domain-detach  disable -> wait for deploy -> delete -> release
#   tenant-offboarding    block, disable + sign out users, detach domains
#
# No Lambda code: every step is a direct AWS SDK integration (DynamoDB,
# Cognito, CloudFront, S3, SNS) or an HTTP task to the Stripe API through an
# EventBridge connection that holds the platform key. The definitions are
# JSONata ASL files in definitions/ - open them in Workflow Studio to see the
# graphs. Each workflow has its own role scoped to exactly its steps.

data "aws_caller_identity" "current" {}

locals {
  prefix     = var.environment == "prod" ? "" : "${var.environment}-"
  account_id = data.aws_caller_identity.current.account_id

  names = {
    onboarding    = "${local.prefix}tenant-onboarding"
    domain_attach = "${local.prefix}tenant-domain-attach"
    domain_detach = "${local.prefix}tenant-domain-detach"
    offboarding   = "${local.prefix}tenant-offboarding"
  }
  state_machine_arns = { for k, n in local.names : k => "arn:aws:states:${var.region}:${local.account_id}:stateMachine:${n}" }

  # var.default_tax_rates as the list the onboarding Map state iterates over.
  tax_rates = [for key, rate in var.default_tax_rates : {
    key          = key
    display_name = rate.display_name
    percentage   = rate.percentage
    inclusive    = rate.inclusive
  }]

  common_template_vars = {
    environment             = var.environment
    tenant_table            = var.tenant_table_name
    alert_topic_arn         = var.alert_topic_arn
    platform_domain_enabled = var.platform_domain_enabled ? "true" : "false"
    platform_domain         = var.platform_domain
    distribution_id         = var.multitenant_distribution_id
    connection_group_id     = var.connection_group_id
    cname_target            = var.cname_target
  }

  cloudfront_tenant_resources = var.platform_domain_enabled ? [
    "arn:aws:cloudfront::${local.account_id}:distribution-tenant/*",
    var.multitenant_distribution_arn,
    var.connection_group_arn,
  ] : []
}

# --- Stripe API access for the HTTP tasks ------------------------------------
#
# Holds the platform Stripe key as an API-key header. EventBridge stores it in
# its own Secrets Manager secret (events!connection/...), which only the
# onboarding role can read. Same key as the Terraform Stripe provider (the
# pipeline's STRIPE_SECRET_KEY_* secret) - see docs/PLATFORM-SETUP.md for the
# restricted-key permissions it needs.
resource "aws_cloudwatch_event_connection" "stripe" {
  name               = "${local.prefix}stripe-platform-api"
  description        = "Platform Stripe API key for the tenant-onboarding HTTP tasks"
  authorization_type = "API_KEY"

  auth_parameters {
    api_key {
      key   = "Authorization"
      value = "Bearer ${var.stripe_secret_key}"
    }
  }
}

# --- Logging -------------------------------------------------------------------
#
# ERROR level without execution data: failures are visible, but owner emails
# and Stripe responses don't get copied into CloudWatch Logs. The full
# history of each execution stays in the Step Functions console (90 days).
resource "aws_cloudwatch_log_group" "this" {
  for_each = local.names

  name              = "/aws/vendedlogs/states/${each.value}"
  retention_in_days = 30

  tags = {
    Environment = var.environment
  }
}

# --- Roles ------------------------------------------------------------------------

data "aws_iam_policy_document" "assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["states.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }
  }
}

resource "aws_iam_role" "this" {
  for_each = local.names

  name               = "${each.value}-role"
  assume_role_policy = data.aws_iam_policy_document.assume.json

  tags = {
    Environment = var.environment
  }
}

# Step Functions log delivery - these actions have no resource-level
# permissions, so "*" is the documented requirement. Shared by all four.
data "aws_iam_policy_document" "common" {
  statement {
    sid = "VendedLogDelivery"
    actions = [
      "logs:CreateLogDelivery",
      "logs:GetLogDelivery",
      "logs:UpdateLogDelivery",
      "logs:DeleteLogDelivery",
      "logs:ListLogDeliveries",
      "logs:PutResourcePolicy",
      "logs:DescribeResourcePolicies",
      "logs:DescribeLogGroups",
    ]
    resources = ["*"]
  }

  statement {
    sid       = "NotifyOperators"
    actions   = ["sns:Publish"]
    resources = [var.alert_topic_arn]
  }
}

data "aws_iam_policy_document" "onboarding" {
  source_policy_documents = [data.aws_iam_policy_document.common.json]

  statement {
    sid       = "TenantRows"
    actions   = ["dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:UpdateItem", "dynamodb:ConditionCheckItem"]
    resources = [var.tenant_table_arn]
  }

  statement {
    sid       = "OwnerProfile"
    actions   = ["dynamodb:PutItem"]
    resources = [var.user_table_arn]
  }

  statement {
    sid       = "InviteFirstOwner"
    actions   = ["cognito-idp:AdminCreateUser", "cognito-idp:AdminGetUser", "cognito-idp:AdminAddUserToGroup"]
    resources = [var.tenant_user_pool_arn]
  }

  statement {
    sid       = "CallStripeApi"
    actions   = ["states:InvokeHTTPEndpoint"]
    resources = [local.state_machine_arns.onboarding]

    condition {
      test     = "StringEquals"
      variable = "states:HTTPMethod"
      values   = ["POST"]
    } 

    # Exactly the two endpoints onboarding calls: account creation (Accounts
    # v2) and the restaurant's VAT rates (v1, on the connected account).
    condition {
      test     = "StringEquals"
      variable = "states:HTTPEndpoint"
      values = [
        "https://api.stripe.com/v2/core/accounts",
        "https://api.stripe.com/v1/tax_rates",
      ]
    }
  }

  statement {
    sid       = "UseStripeConnection"
    actions   = ["events:RetrieveConnectionCredentials"]
    resources = [aws_cloudwatch_event_connection.stripe.arn]
  }

  statement {
    sid       = "ReadStripeConnectionSecret"
    actions   = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"]
    resources = [aws_cloudwatch_event_connection.stripe.secret_arn]
  }

  dynamic "statement" {
    for_each = var.platform_domain_enabled ? [1] : []
    content {
      sid       = "CreateSubdomainTenant"
      actions   = ["cloudfront:CreateDistributionTenant", "cloudfront:GetDistributionTenant"]
      resources = local.cloudfront_tenant_resources
    }
  }

  dynamic "statement" {
    for_each = var.platform_domain_enabled ? [1] : []
    content {
      sid       = "SeedSitePlaceholder"
      actions   = ["s3:GetObject", "s3:PutObject"]
      resources = ["${var.sites_bucket_arn}/*"]
    }
  }

  # Without ListBucket, S3 answers a missing key with 403 instead of 404 -
  # the "is a site deployed yet?" check relies on telling the two apart.
  dynamic "statement" {
    for_each = var.platform_domain_enabled ? [1] : []
    content {
      sid       = "TellMissingFromForbidden"
      actions   = ["s3:ListBucket"]
      resources = [var.sites_bucket_arn]
    }
  }
}

data "aws_iam_policy_document" "domain_attach" {
  source_policy_documents = [data.aws_iam_policy_document.common.json]

  statement {
    sid       = "TenantDomainRows"
    actions   = ["dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:UpdateItem", "dynamodb:ConditionCheckItem"]
    resources = [var.tenant_table_arn]
  }

  dynamic "statement" {
    for_each = var.platform_domain_enabled ? [1] : []
    content {
      sid       = "CreateDomainTenant"
      actions   = ["cloudfront:CreateDistributionTenant", "cloudfront:GetDistributionTenant", "cloudfront:GetManagedCertificateDetails"]
      resources = local.cloudfront_tenant_resources
    }
  }

  # CloudFront requests the managed (HTTP-validated) ACM certificate on the
  # caller's behalf. RequestCertificate has no resource-level scope.
  dynamic "statement" {
    for_each = var.platform_domain_enabled ? [1] : []
    content {
      sid       = "ManagedCertificate"
      actions   = ["acm:RequestCertificate", "acm:DescribeCertificate"]
      resources = ["*"]
    }
  }
}

data "aws_iam_policy_document" "domain_detach" {
  source_policy_documents = [data.aws_iam_policy_document.common.json]

  statement {
    sid       = "TenantDomainRows"
    actions   = ["dynamodb:GetItem", "dynamodb:UpdateItem", "dynamodb:DeleteItem", "dynamodb:ConditionCheckItem"]
    resources = [var.tenant_table_arn]
  }

  dynamic "statement" {
    for_each = var.platform_domain_enabled ? [1] : []
    content {
      sid       = "RemoveDomainTenant"
      actions   = ["cloudfront:GetDistributionTenant", "cloudfront:UpdateDistributionTenant", "cloudfront:DeleteDistributionTenant"]
      resources = local.cloudfront_tenant_resources
    }
  }
}

data "aws_iam_policy_document" "offboarding" {
  source_policy_documents = [data.aws_iam_policy_document.common.json]

  statement {
    sid       = "TenantRows"
    actions   = ["dynamodb:UpdateItem", "dynamodb:Query"]
    resources = [var.tenant_table_arn]
  }

  statement {
    sid       = "ListTenantUsers"
    actions   = ["dynamodb:Query"]
    resources = ["${var.user_table_arn}/index/${var.user_tenant_index_name}"]
  }

  statement {
    sid       = "DisableTenantUsers"
    actions   = ["cognito-idp:AdminDisableUser", "cognito-idp:AdminUserGlobalSignOut"]
    resources = [var.tenant_user_pool_arn]
  }

  statement {
    sid       = "RunDomainDetach"
    actions   = ["states:StartExecution"]
    resources = [local.state_machine_arns.domain_detach]
  }

  statement {
    sid       = "WaitForDomainDetach"
    actions   = ["states:DescribeExecution", "states:StopExecution"]
    resources = ["arn:aws:states:${var.region}:${local.account_id}:execution:${local.names.domain_detach}:*"]
  }

  # .sync:2 completion is delivered through this Step Functions-managed rule.
  statement {
    sid       = "SyncExecutionEvents"
    actions   = ["events:PutTargets", "events:PutRule", "events:DescribeRule"]
    resources = ["arn:aws:events:${var.region}:${local.account_id}:rule/StepFunctionsGetEventsForStepFunctionsExecutionRule"]
  }
}

resource "aws_iam_role_policy" "onboarding" {
  name   = "tenant-onboarding"
  role   = aws_iam_role.this["onboarding"].id
  policy = data.aws_iam_policy_document.onboarding.json
}

resource "aws_iam_role_policy" "domain_attach" {
  name   = "tenant-domain-attach"
  role   = aws_iam_role.this["domain_attach"].id
  policy = data.aws_iam_policy_document.domain_attach.json
}

resource "aws_iam_role_policy" "domain_detach" {
  name   = "tenant-domain-detach"
  role   = aws_iam_role.this["domain_detach"].id
  policy = data.aws_iam_policy_document.domain_detach.json
}

resource "aws_iam_role_policy" "offboarding" {
  name   = "tenant-offboarding"
  role   = aws_iam_role.this["offboarding"].id
  policy = data.aws_iam_policy_document.offboarding.json
}

# --- State machines ---------------------------------------------------------------

resource "aws_sfn_state_machine" "onboarding" {
  name     = local.names.onboarding
  role_arn = aws_iam_role.this["onboarding"].arn
  definition = templatefile("${path.module}/definitions/onboarding.asl.json", merge(local.common_template_vars, {
    user_table            = var.user_table_name
    user_pool_id          = var.tenant_user_pool_id
    owner_group           = var.owner_group_name
    stripe_connection_arn = aws_cloudwatch_event_connection.stripe.arn
    stripe_api_version    = var.stripe_api_version
    tax_rates_json        = jsonencode(local.tax_rates)
    sites_bucket          = var.sites_bucket_name
    placeholder_key       = var.site_placeholder_key
  }))

  logging_configuration {
    log_destination        = "${aws_cloudwatch_log_group.this["onboarding"].arn}:*"
    include_execution_data = false
    level                  = "ERROR"
  }

  tags = {
    Environment = var.environment
  }

  depends_on = [aws_iam_role_policy.onboarding]
}

resource "aws_sfn_state_machine" "domain_attach" {
  name     = local.names.domain_attach
  role_arn = aws_iam_role.this["domain_attach"].arn
  definition = templatefile("${path.module}/definitions/domain-attach.asl.json", merge(local.common_template_vars, {
    certificate_check_interval_seconds = var.certificate_check_interval_seconds
    max_certificate_checks             = var.max_certificate_checks
  }))

  logging_configuration {
    log_destination        = "${aws_cloudwatch_log_group.this["domain_attach"].arn}:*"
    include_execution_data = false
    level                  = "ERROR"
  }

  tags = {
    Environment = var.environment
  }

  depends_on = [aws_iam_role_policy.domain_attach]
}

resource "aws_sfn_state_machine" "domain_detach" {
  name       = local.names.domain_detach
  role_arn   = aws_iam_role.this["domain_detach"].arn
  definition = templatefile("${path.module}/definitions/domain-detach.asl.json", local.common_template_vars)

  logging_configuration {
    log_destination        = "${aws_cloudwatch_log_group.this["domain_detach"].arn}:*"
    include_execution_data = false
    level                  = "ERROR"
  }

  tags = {
    Environment = var.environment
  }

  depends_on = [aws_iam_role_policy.domain_detach]
}

resource "aws_sfn_state_machine" "offboarding" {
  name     = local.names.offboarding
  role_arn = aws_iam_role.this["offboarding"].arn
  definition = templatefile("${path.module}/definitions/offboarding.asl.json", merge(local.common_template_vars, {
    user_table                      = var.user_table_name
    user_tenant_index               = var.user_tenant_index_name
    user_pool_id                    = var.tenant_user_pool_id
    domain_detach_state_machine_arn = aws_sfn_state_machine.domain_detach.arn
  }))

  logging_configuration {
    log_destination        = "${aws_cloudwatch_log_group.this["offboarding"].arn}:*"
    include_execution_data = false
    level                  = "ERROR"
  }

  tags = {
    Environment = var.environment
  }

  depends_on = [aws_iam_role_policy.offboarding]
}

# --- Alarms -------------------------------------------------------------------------
#
# Every failure path inside the workflows already emails the operators with
# the tenant and the cause. These catch what the workflows can't report
# themselves: an execution that hit its overall timeout.
resource "aws_cloudwatch_metric_alarm" "timed_out" {
  for_each = local.names

  alarm_name          = "${each.value}-timed-out"
  alarm_description   = "A ${each.value} execution hit its overall TimeoutSeconds - check the execution in the Step Functions console."
  namespace           = "AWS/States"
  metric_name         = "ExecutionsTimedOut"
  dimensions          = { StateMachineArn = local.state_machine_arns[each.key] }
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [var.alert_topic_arn]

  tags = {
    Environment = var.environment
  }
}
