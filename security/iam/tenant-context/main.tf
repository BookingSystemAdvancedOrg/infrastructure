# Read access every tenant-aware Lambda needs to answer "which tenant is
# this request for, and is it allowed?" - one managed policy attached to
# all of their roles (root config.tf, local.tenant_aware_role_names), so
# the rule can't drift between ~40 hand-written role modules.
#
#   - tenant table: GetItem / Query. The PROFILE row says whether the tenant
#     is active, which plan features it has, its Stripe connected account,
#     sender name and site URL. Base table only - deliberately no Scan and
#     no GSI1: both would list every customer's profile, and no request
#     ever needs that (listing tenants is /platform/* only).
#   - location table, byLocationId index: Query. Public routes only know
#     {locationId}; this resolves it to its tenantId.
#
# Writes stay in each Lambda's own role (e.g. platform-tenants owns the
# tenant table, create-location bumps locationCount).

locals {
  policy_name = var.environment == "prod" ? "tenant-context-read" : "${var.environment}-tenant-context-read"
}

resource "aws_iam_policy" "this" {
  name        = local.policy_name
  description = "Resolve and check the caller's tenant: read the tenant table and the location table's locationId index"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ReadTenantRows"
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:Query",
        ]
        Resource = "${var.tenant_table_arn}"
      },
      {
        Sid      = "ResolveLocationToTenant"
        Effect   = "Allow"
        Action   = "dynamodb:Query"
        Resource = "${var.location_table_arn}/index/${var.location_id_index_name}"
      }
    ]
  })

  tags = {
    Environment = var.environment
  }
}

resource "aws_iam_role_policy_attachment" "this" {
  for_each = var.role_names

  role       = each.value
  policy_arn = aws_iam_policy.this.arn
}
