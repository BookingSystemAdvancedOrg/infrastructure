# Restaurant terms acceptance (POST /tenant/terms/accept, application
# shared/terms.py): the same shape as dpa-iam.tf.
#
# - PutItem only where the partition key starts with "TERMS#" (LeadingKeys).
# - UpdateItem only of the `terms` attribute on the PROFILE. No ALL_OLD/ALL_NEW.
resource "aws_iam_role_policy" "terms_acceptance" {
  name = "terms-acceptance"
  role = aws_iam_role.this.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "AppendTermsAcceptanceRows"
        Effect   = "Allow"
        Action   = ["dynamodb:PutItem"]
        Resource = "${var.tenant_table_arn}"
        Condition = {
          "ForAllValues:StringLike" = {
            "dynamodb:LeadingKeys" = ["TERMS#*"]
          }
          StringEqualsIfExists = {
            "dynamodb:ReturnValues" = ["NONE"]
          }
        }
      },
      {
        Sid      = "TermsSummaryOnProfileOnly"
        Effect   = "Allow"
        Action   = ["dynamodb:UpdateItem"]
        Resource = "${var.tenant_table_arn}"
        Condition = {
          "ForAllValues:StringEquals" = {
            "dynamodb:Attributes" = ["PK", "SK", "terms"]
          }
          StringEqualsIfExists = {
            "dynamodb:ReturnValues" = ["NONE", "UPDATED_OLD", "UPDATED_NEW"]
          }
        }
      }
    ]
  })
}
