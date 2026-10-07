# Execution role for the PlatformTenantsFn Lambda - the /platform/* API the
# operator console (sbs-admin repo, which also holds this Lambda's code) calls (operator pool token + platform/admin scope,
# enforced by API Gateway before this Lambda runs).
#
# Owns the tenant table (create/update tenants, plans, domains rows) and
# starts the provisioning workflows instead of provisioning anything itself:
# onboarding, domain attach/detach and offboarding are Step Functions state
# machines (orchestration/tenant-workflows), so this role can start them but
# holds none of their Cognito/CloudFront/Stripe-account permissions.
#
# Cognito actions are for suspend/resume (disable/enable + global sign-out
# of every user of the tenant) and for inviting additional owners.

data "aws_caller_identity" "current" {}

locals {
  function_name = var.environment == "prod" ? "platform-tenants" : "${var.environment}-platform-tenants"
}

resource "aws_iam_role" "this" {
  name = "${local.function_name}-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { Service = "lambda.amazonaws.com" }
        Action    = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Environment = var.environment
  }
}

resource "aws_iam_role_policy" "tenant_table" {
  name = "tenant-table-write"
  role = aws_iam_role.this.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # Item-level only - no table-level actions (DeleteTable, UpdateTable,
        # PITR) for an application role, and no Scan.
        Sid    = "ItemAccessTenantTable"
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:BatchGetItem",
          "dynamodb:Query",
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem",
          "dynamodb:ConditionCheckItem",
        ]
        Resource = [
          "${var.tenant_table_arn}",
          "${var.tenant_table_arn}/index/*",
        ]
      }
    ]
  })
}

# Operators manage a tenant's locations from sbs-admin (a customer opening
# another restaurant): item-level writes only, always under TENANT#<id> keys.
resource "aws_iam_role_policy" "location_table" {
  name = "location-table"
  role = aws_iam_role.this.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ReadLocationTable"
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:Query",
        ]
        Resource = [
          "${var.location_table_arn}",
          "${var.location_table_arn}/index/*",
        ]
      },
      {
        Sid    = "ManageTenantLocations"
        Effect = "Allow"
        Action = [
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem",
        ]
        Resource = "${var.location_table_arn}"
      }
    ]
  })
}

# Read (list a tenant's users via byTenant for suspend/resume and the tenant
# detail page) + PutItem for the profile row of an additional owner invited
# from the dashboard (POST /platform/tenants/{tenantId}/owners). The first
# owner's profile is written by the onboarding workflow, not by this Lambda.
resource "aws_iam_role_policy" "user_table" {
  name = "user-table"
  role = aws_iam_role.this.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ReadUserTable"
        Effect = "Allow"
        Action = [
          "dynamodb:Scan",
          "dynamodb:GetItem",
          "dynamodb:Query",
        ]
        Resource = [
          "${var.user_table_arn}",
          "${var.user_table_arn}/index/*",
        ]
      },
      {
        Sid    = "CreateOwnerProfile"
        Effect = "Allow"
        Action = [
          "dynamodb:PutItem",
        ]
        Resource = "${var.user_table_arn}"
      }
    ]
  })
}

resource "aws_iam_role_policy" "cognito" {
  name = "tenant-user-pool-admin"
  role = aws_iam_role.this.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ManageTenantUsers"
        Effect = "Allow"
        Action = [
          "cognito-idp:AdminCreateUser",
          "cognito-idp:AdminAddUserToGroup",
          "cognito-idp:AdminGetUser",
          "cognito-idp:AdminDisableUser",
          "cognito-idp:AdminEnableUser",
          "cognito-idp:AdminUserGlobalSignOut",
        ]
        Resource = "${var.tenant_user_pool_arn}"
      },
      {
        # Operators manage each other from sbs-admin (Operators page).
        Sid    = "ManageOperators"
        Effect = "Allow"
        Action = [
          "cognito-idp:ListUsersInGroup",
          "cognito-idp:AdminGetUser",
          "cognito-idp:AdminCreateUser",
          "cognito-idp:AdminAddUserToGroup",
          "cognito-idp:AdminUpdateUserAttributes",
          "cognito-idp:AdminDisableUser",
          "cognito-idp:AdminEnableUser",
          "cognito-idp:AdminUserGlobalSignOut",
          "cognito-idp:AdminDeleteUser",
        ]
        Resource = "${var.operator_user_pool_arn}"
      }
    ]
  })
}

resource "aws_iam_role_policy" "start_workflows" {
  name = "tenant-workflows-start"
  role = aws_iam_role.this.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "StartTenantWorkflows"
        Effect = "Allow"
        Action = [
          "states:StartExecution",
        ]
        Resource = [
          "${var.onboarding_state_machine_arn}",
          "${var.domain_attach_state_machine_arn}",
          "${var.domain_detach_state_machine_arn}",
          "${var.offboarding_state_machine_arn}",
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy" "describe_workflows" {
  name = "tenant-workflows-describe"
  role = aws_iam_role.this.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ReadTenantWorkflowStatus"
        Effect = "Allow"
        Action = [
          "states:DescribeExecution",
        ]
        Resource = [
          "${replace(var.onboarding_state_machine_arn, ":stateMachine:", ":execution:")}:*",
          "${replace(var.domain_attach_state_machine_arn, ":stateMachine:", ":execution:")}:*",
          "${replace(var.domain_detach_state_machine_arn, ":stateMachine:", ":execution:")}:*",
          "${replace(var.offboarding_state_machine_arn, ":stateMachine:", ":execution:")}:*",
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy" "stripe_secret" {
  name = "platform-stripe-secret"
  role = aws_iam_role.this.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ReadPlatformStripeKey"
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
        ]
        Resource = "${var.stripe_secret_arn}"
      }
    ]
  })
}

# Scoped to exactly this function's own log group - not logs:* on everything.
# No logs:CreateLogGroup: the log group is provisioned explicitly alongside
# the function (compute/lambda/<name>) with a real retention period.
resource "aws_iam_role_policy" "logs" {
  name = "cloudwatch-logs"
  role = aws_iam_role.this.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "WriteOwnLogGroup"
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents",
        ]
        Resource = "arn:aws:logs:${var.region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/${local.function_name}:*"
      }
    ]
  })
}
