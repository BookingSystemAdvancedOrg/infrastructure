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
#   - location table, GetItem: with the tenant known, the location row is
#     read by its key TENANT#<t>/LOCATION#<l> (strongly consistent, so a
#     location is usable the moment it is created; a key under another
#     tenant simply isn't found). Exposes nothing the index doesn't already
#     return. No Scan/Query on the base table - listing a tenant's locations
#     stays with get-location/create-location's own roles.
#
# Writes stay in each Lambda's own role (e.g. platform-tenants owns the
# tenant table, create-location bumps locationCount).

locals {
  policy_name = var.environment == "prod" ? "tenant-context-read" : "${var.environment}-tenant-context-read"
}

resource "aws_iam_policy" "this" {
  name        = local.policy_name
  description = "Resolve and check the caller's tenant: read the tenant table, location rows by key and the locationId index"

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
      },
      {
        Sid      = "ReadLocationOfTenant"
        Effect   = "Allow"
        Action   = "dynamodb:GetItem"
        Resource = "${var.location_table_arn}"
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

# Staff are limited to the location in their own profile. Only the functions
# staff may call get this, and only GetItem by key - no Query/Scan, so no
# listing of anyone's users.
resource "aws_iam_policy" "staff_location" {
  name        = var.environment == "prod" ? "tenant-context-staff-location" : "${var.environment}-tenant-context-staff-location"
  description = "Read the caller's own user profile by key (staff location assignment and status)"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ReadCallerProfile"
        Effect   = "Allow"
        Action   = "dynamodb:GetItem"
        Resource = "${var.user_table_arn}"
      }
    ]
  })

  tags = {
    Environment = var.environment
  }
}

resource "aws_iam_role_policy_attachment" "staff_location" {
  for_each = var.staff_check_role_names

  role       = each.value
  policy_arn = aws_iam_policy.staff_location.arn
}
