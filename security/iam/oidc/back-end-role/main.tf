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
            "token.actions.githubusercontent.com:sub" = "repo:${var.github_repo}:*"
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
      }
    ]
  })
}
