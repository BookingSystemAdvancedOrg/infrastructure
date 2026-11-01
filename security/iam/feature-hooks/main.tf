# IAM change: owner to approve before merge (Run 0).
#
# Adds one inline policy "feature-hooks" to eleven EXISTING execution roles:
# lambda:InvokeFunction on the exact live alias ARN of the feature API
# Lambdas each caller sends a feature hook to (CONTRACTS.md sections 9 and
# 14, rows 1-10). Nothing else: no feature table names or other actions on
# the callers, and no OIDC/deploy role, deploy_boundary or sites bucket
# policy is touched. Invoking a feature that is not deployed yet fails with
# ResourceNotFoundException, which shared/feature_hooks.py skips.

locals {
  prefix = var.environment == "prod" ? "" : "${var.environment}-"

  all_features = [
    "meta-ads", "site-builder", "guest-crm", "google-business", "gift-cards",
    "waitlist", "social-posting", "personalliggare", "accounting-sync", "dish-margin",
  ]

  # caller key (var.role_names) => [{ sid, targets }]
  grants = {
    guest_privacy = [
      { sid = "PrivacyExportEraseHooks", targets = ["guest-crm", "google-business", "gift-cards", "waitlist"] },
    ]
    tenant_purge           = [{ sid = "TenantPurgeHook", targets = local.all_features }]
    stripe_webhook         = [{ sid = "StripeEventHook", targets = ["gift-cards"] }]
    payment_intent         = [{ sid = "CheckoutGiftcardReserveHook", targets = ["gift-cards"] }]
    webhook_payment_intent = [{ sid = "CheckoutGiftcardReverseHook", targets = ["gift-cards"] }]
    kassa                  = [{ sid = "KassaGiftcardHook", targets = ["gift-cards"] }]
    accounting             = [{ sid = "AccountingEventsHook", targets = ["gift-cards"] }]
    insights               = [{ sid = "InsightsDishCostsHook", targets = ["dish-margin"] }]
    marketing              = [{ sid = "MarketingSegmentHook", targets = ["guest-crm"] }]
    marketing_send         = [{ sid = "MarketingSegmentHook", targets = ["guest-crm"] }]
    platform_tenants = [
      { sid = "PlatformForwardHook", targets = ["meta-ads", "site-builder", "google-business", "personalliggare"] },
    ]
  }
}

resource "aws_iam_role_policy" "this" {
  for_each = local.grants

  name = "feature-hooks"
  role = var.role_names[each.key]

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      for g in each.value : {
        Sid      = g.sid
        Effect   = "Allow"
        Action   = "lambda:InvokeFunction"
        Resource = [for f in g.targets : "arn:aws:lambda:${var.region}:${var.account_id}:function:${local.prefix}${f}:live"]
      }
    ]
  })
}
