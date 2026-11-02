# IAM change: owner to approve before merge (Run 0).
#
# Adds one inline policy "feature-hooks" to twelve EXISTING execution roles:
# lambda:InvokeFunction on the exact live alias ARN of the feature API
# Lambdas each caller sends a feature hook to (CONTRACTS.md sections 9 and
# 14, rows 1-10; the Run 0 addendum adds rows 11-16, events-tickets and
# phone-agent, IAM change: owner to approve). Nothing else: no feature
# table names or other actions on the callers, and no OIDC/deploy role,
# deploy_boundary or sites bucket policy is touched. Invoking a feature
# that is not deployed yet fails with ResourceNotFoundException, which
# shared/feature_hooks.py skips.

locals {
  prefix = var.environment == "prod" ? "" : "${var.environment}-"

  all_features = [
    "meta-ads", "site-builder", "guest-crm", "google-business", "gift-cards",
    "waitlist", "social-posting", "personalliggare", "accounting-sync", "dish-margin",
    "events-tickets", "phone-agent", # Run 0 addendum (row 12)
  ]

  # caller key (var.role_names) => [{ sid, targets }]
  grants = {
    guest_privacy = [
      {
        sid     = "PrivacyExportEraseHooks"
        targets = ["guest-crm", "google-business", "gift-cards", "waitlist", "events-tickets", "phone-agent"] # + row 11
      },
    ]
    tenant_purge           = [{ sid = "TenantPurgeHook", targets = local.all_features }]
    stripe_webhook         = [{ sid = "StripeEventHook", targets = ["gift-cards", "events-tickets"] }] # + row 13
    payment_intent         = [{ sid = "CheckoutGiftcardReserveHook", targets = ["gift-cards"] }]
    webhook_payment_intent = [{ sid = "CheckoutGiftcardReverseHook", targets = ["gift-cards"] }]
    manage_order           = [{ sid = "CheckoutGiftcardRefundHook", targets = ["gift-cards"] }]
    kassa                  = [{ sid = "KassaGiftcardHook", targets = ["gift-cards"] }]
    accounting             = [{ sid = "AccountingEventsHook", targets = ["gift-cards", "events-tickets"] }] # + row 14
    insights = [
      { sid = "InsightsDishCostsHook", targets = ["dish-margin"] },
      { sid = "InsightsEventsHook", targets = ["events-tickets"] }, # row 15
    ]
    marketing      = [{ sid = "MarketingSegmentHook", targets = ["guest-crm"] }]
    marketing_send = [{ sid = "MarketingSegmentHook", targets = ["guest-crm"] }]
    platform_tenants = [
      {
        # one statement: operator forwards and billing.usage (row 16, phone-agent:live only)
        sid     = "PlatformForwardHook"
        targets = ["meta-ads", "site-builder", "google-business", "personalliggare", "phone-agent"] # + row 16
      },
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
