# Role assumed by the backend repo's GitHub Actions pipeline via OIDC - no
# long-lived AWS credentials stored as a repo secret. This one repo builds
# and deploys all 20 Lambda functions, so unlike the two front-end roles
# (each scoped to exactly one bucket/distribution), this role is scoped to
# every ECR repository and every Lambda function in the account rather
# than listing 20 near-identical ARNs by hand - still scoped to this
# account/region/service, not a bare "*", and still nothing outside
# ECR push + Lambda code deploy (no S3, no CloudFront, no DynamoDB, no
# IAM).

data "aws_caller_identity" "current" {}

locals {
  role_name = var.environment == "prod" ? "back-end-deploy-role" : "${var.environment}-back-end-deploy-role"
}

resource "aws_iam_role" "this" {
  name = local.role_name

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { Federated = "${var.oidc_provider_arn}" }
        Action    = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          }
          # Repo-wide, any branch/event for now - tighten to a specific
          # ref (e.g. "repo:${var.github_repo}:ref:refs/heads/main") once
          # this repo's branch/deploy strategy is settled.
          StringLike = {
            "token.actions.githubusercontent.com:sub" = "repo:${var.github_repo}@*:*"
          }
        }
      }
    ]
  })

  tags = {
    Environment = var.environment
  }
}

# GetAuthorizationToken has no resource-level permissions in AWS - it's
# always Resource = "*", regardless of which repos you actually push to.
# It only grants the ability to obtain a login token, not access to any
# specific repository - that's what the second statement scopes.
resource "aws_iam_role_policy" "ecr_push" {
  name = "ecr-push-all-repos"
  role = aws_iam_role.this.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "GetECRLoginToken"
        Effect   = "Allow"
        Action   = "ecr:GetAuthorizationToken"
        Resource = "*"
      },
      {
        Sid    = "PushToAnyRepoInThisAccount"
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload",
          "ecr:PutImage",
        ]
        Resource = "arn:aws:ecr:${var.region}:${data.aws_caller_identity.current.account_id}:repository/*"
      },
      {
        Sid    = "NotTheOperatorApiRepo"
        Effect = "Deny"
        Action = [
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload",
          "ecr:PutImage",
        ]
        Resource = [
          "arn:aws:ecr:${var.region}:${data.aws_caller_identity.current.account_id}:repository/platform-tenants",
          "arn:aws:ecr:${var.region}:${data.aws_caller_identity.current.account_id}:repository/*-platform-tenants",
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy" "lambda_deploy" {
  name = "lambda-update-code-all-functions"
  role = aws_iam_role.this.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "UpdateAndReadAnyFunctionInThisAccount"
        Effect = "Allow"
        Action = [
          "lambda:UpdateFunctionCode",
          "lambda:GetFunction",
          "lambda:GetFunctionConfiguration",
        ]
        Resource = "arn:aws:lambda:${var.region}:${data.aws_caller_identity.current.account_id}:function:*"
      },
      {
        # pre-token-generation decides every token's tenant_id - its code is
        # owned and deployed by this infra repo only. A backend workflow (any
        # branch) must never be able to swap it.
        Sid    = "NeverTouchTheTenantClaimTrigger"
        Effect = "Deny"
        Action = [
          "lambda:UpdateFunctionCode",
          "lambda:UpdateFunctionConfiguration",
        ]
        Resource = [
          "arn:aws:lambda:${var.region}:${data.aws_caller_identity.current.account_id}:function:pre-token-generation",
          "arn:aws:lambda:${var.region}:${data.aws_caller_identity.current.account_id}:function:*-pre-token-generation",
          # platform-tenants (the operator API) is built and deployed by the
          # sbs-admin repo - a backend workflow must not replace it.
          "arn:aws:lambda:${var.region}:${data.aws_caller_identity.current.account_id}:function:platform-tenants",
          "arn:aws:lambda:${var.region}:${data.aws_caller_identity.current.account_id}:function:*-platform-tenants",
        ]
      }
    ]
  })
}

# Blue/green releases (ci/lambda-release.sh): publish the new code as a
# version, shift the "live" alias through CodeDeploy, email the result -
# and on a failed release put the previous image back on :latest/$LATEST.
resource "aws_iam_role_policy" "lambda_release" {
  name = "lambda-blue-green-release"
  role = aws_iam_role.this.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "PublishVersionsAndReadAliases"
        Effect = "Allow"
        Action = [
          "lambda:PublishVersion",
          "lambda:GetAlias",
          "lambda:ListVersionsByFunction",
        ]
        Resource = [
          "arn:aws:lambda:${var.region}:${data.aws_caller_identity.current.account_id}:function:*",
        ]
      },
      {
        Sid      = "ManualRollbackMovesTheLiveAlias"
        Effect   = "Allow"
        Action   = "lambda:UpdateAlias"
        Resource = "arn:aws:lambda:${var.region}:${data.aws_caller_identity.current.account_id}:function:*:live"
      },
      {
        Sid    = "NotTheOperatorApiOrTheClaimTrigger"
        Effect = "Deny"
        Action = [
          "lambda:PublishVersion",
          "lambda:UpdateAlias",
        ]
        Resource = [
          "arn:aws:lambda:${var.region}:${data.aws_caller_identity.current.account_id}:function:pre-token-generation*",
          "arn:aws:lambda:${var.region}:${data.aws_caller_identity.current.account_id}:function:*-pre-token-generation*",
          "arn:aws:lambda:${var.region}:${data.aws_caller_identity.current.account_id}:function:platform-tenants*",
          "arn:aws:lambda:${var.region}:${data.aws_caller_identity.current.account_id}:function:*-platform-tenants*",
        ]
      },
      {
        Sid    = "RunReleasesInTheLambdaReleasesApp"
        Effect = "Allow"
        Action = [
          "codedeploy:CreateDeployment",
          "codedeploy:GetDeployment",
          "codedeploy:GetDeploymentGroup",
          "codedeploy:StopDeployment",
          "codedeploy:ListDeployments",
          "codedeploy:GetApplicationRevision",
          "codedeploy:RegisterApplicationRevision",
        ]
        Resource = [
          "arn:aws:codedeploy:${var.region}:${data.aws_caller_identity.current.account_id}:application:${var.codedeploy_app_name}",
          "arn:aws:codedeploy:${var.region}:${data.aws_caller_identity.current.account_id}:deploymentgroup:${var.codedeploy_app_name}/*",
        ]
      },
      {
        Sid      = "ReadDeploymentConfigs"
        Effect   = "Allow"
        Action   = "codedeploy:GetDeploymentConfig"
        Resource = "arn:aws:codedeploy:${var.region}:${data.aws_caller_identity.current.account_id}:deploymentconfig:*"
      },
      {
        Sid    = "ReadImagesToRestoreOnRollback"
        Effect = "Allow"
        Action = [
          "ecr:BatchGetImage",
          "ecr:DescribeImages",
        ]
        Resource = "arn:aws:ecr:${var.region}:${data.aws_caller_identity.current.account_id}:repository/*"
      },
      {
        Sid      = "EmailReleaseResults"
        Effect   = "Allow"
        Action   = "sns:Publish"
        Resource = var.alert_topic_arn
      }
    ]
  })
}
