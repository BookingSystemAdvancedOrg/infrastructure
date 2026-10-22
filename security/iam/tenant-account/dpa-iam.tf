# DPA acceptance (POST /tenant/dpa/accept, application shared/dpa.py).
#
# One transaction: PutItem of a new acceptance row in its own DPA#<tenant>
# partition, and UpdateItem of the `dpa` summary on the tenant PROFILE.
#
# - PutItem only where the partition key starts with "DPA#" (LeadingKeys), so
#   even a bug can't overwrite a PROFILE, DOMAIN# or any other tenant row.
# - UpdateItem only of the `dpa` attribute, like tenant_profile_edit limits
#   the self-service fields. No ALL_OLD/ALL_NEW.
resource "aws_iam_role_policy" "dpa_acceptance" {
  name = "dpa-acceptance"
  role = aws_iam_role.this.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "AppendDpaAcceptanceRows"
        Effect   = "Allow"
        Action   = ["dynamodb:PutItem"]
        Resource = "${var.tenant_table_arn}"
        Condition = {
          "ForAllValues:StringLike" = {
            "dynamodb:LeadingKeys" = ["DPA#*"]
          }
          StringEqualsIfExists = {
            "dynamodb:ReturnValues" = ["NONE"]
          }
        }
      },
      {
        Sid      = "DpaSummaryOnProfileOnly"
        Effect   = "Allow"
        Action   = ["dynamodb:UpdateItem"]
        Resource = "${var.tenant_table_arn}"
        Condition = {
          "ForAllValues:StringEquals" = {
            "dynamodb:Attributes" = ["PK", "SK", "dpa"]
          }
          StringEqualsIfExists = {
            "dynamodb:ReturnValues" = ["NONE", "UPDATED_OLD", "UPDATED_NEW"]
          }
        }
      }
    ]
  })
}
