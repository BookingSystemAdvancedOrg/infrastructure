# Two properties of dev-platform-tenants-role that plan and validate never
# show (IAM refuses an oversized role only at apply, LimitExceeded):
#   - prod gets no dev twin grant and no mail outbox access, whatever is
#     passed in;
#   - the role's inline policies stay under IAM's 10,240 characters per role.
# Run before adding an inline policy to this role. Mocked AWS, plan only (no
# AWS account, nothing created):
#   terraform -chdir=security/iam/platform-tenants init -backend=false && terraform -chdir=security/iam/platform-tenants test
#
# Inline budget: this module's own inline policies must stay under 9,500
# characters. The rest of the 10,240 is for the inline policies other
# modules put on this role: feature-hooks ("feature-hooks", about 450) and
# site-analytics ("site-analytics-read", about 220). jsonencode output has
# no whitespace, which IAM does not count either, so length() matches IAM.

mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = { account_id = "123456789012" }
  }
}

variables {
  environment                        = "dev"
  region                             = "eu-north-1"
  tenant_table_arn                   = "arn:aws:dynamodb:eu-north-1:123456789012:table/dev-tenant"
  location_table_arn                 = "arn:aws:dynamodb:eu-north-1:123456789012:table/dev-location"
  user_table_arn                     = "arn:aws:dynamodb:eu-north-1:123456789012:table/dev-user"
  tenant_user_pool_arn               = "arn:aws:cognito-idp:eu-north-1:123456789012:userpool/eu-north-1_AbCdEfGhI"
  operator_user_pool_arn             = "arn:aws:cognito-idp:eu-north-1:123456789012:userpool/eu-north-1_JkLmNoPqR"
  onboarding_state_machine_arn       = "arn:aws:states:eu-north-1:123456789012:stateMachine:dev-tenant-onboarding"
  domain_attach_state_machine_arn    = "arn:aws:states:eu-north-1:123456789012:stateMachine:dev-tenant-domain-attach"
  domain_detach_state_machine_arn    = "arn:aws:states:eu-north-1:123456789012:stateMachine:dev-tenant-domain-detach"
  offboarding_state_machine_arn      = "arn:aws:states:eu-north-1:123456789012:stateMachine:dev-tenant-offboarding"
  domain_provision_state_machine_arn = "arn:aws:states:eu-north-1:123456789012:stateMachine:dev-tenant-domain-provision"
  stripe_secret_arn                  = "arn:aws:secretsmanager:eu-north-1:123456789012:secret:dev-stripe/api-key-AbC123"
  domains_enabled                    = true
  domain_documents_bucket_arn        = "arn:aws:s3:::dev-domain-documents-123456789012"
  user_backdrops_bucket_arn          = "arn:aws:s3:::dev-user-backdrops-123456789012"
  user_backdrops_table_arn           = "arn:aws:dynamodb:eu-north-1:123456789012:table/dev-user-backdrops"
  platform_zone_id                   = "Z0123456789ABCDEFGHIJ"
  extra_protected_zone_ids           = ["Z1123456789ABCDEFGHIJ", "Z2123456789ABCDEFGHIJ"]
  site_redirect_kvs_arn              = "arn:aws:cloudfront::123456789012:key-value-store/0a1b2c3d-4e5f-6a7b-8c9d-0e1f2a3b4c5d"
  mail_outbox_enabled                = true
  mail_outbox_bucket_arn             = "arn:aws:s3:::dev-mail-outbox-123456789012"
  ses_identity_arn                   = "arn:aws:ses:eu-north-1:123456789012:identity/mail.dev.booqy.se"
  from_address                       = "no-reply@mail.dev.booqy.se"
  finance_table_arn                  = "arn:aws:dynamodb:eu-north-1:123456789012:table/dev-finance"
  finance_rollup_lambda_arn          = "arn:aws:lambda:eu-north-1:123456789012:function:dev-finance-rollup"
  alert_topic_arn                    = "arn:aws:sns:eu-north-1:123456789012:dev-alerts"
  site_repo_function_arn             = "arn:aws:lambda:eu-north-1:123456789012:function:dev-site-repo:live"
  print_table_arn                    = "arn:aws:dynamodb:eu-north-1:123456789012:table/dev-print"
  manage_user_function_arn           = "arn:aws:lambda:eu-north-1:123456789012:function:dev-manage-user:live"
  tenant_account_function_arn        = "arn:aws:lambda:eu-north-1:123456789012:function:dev-tenant-account:live"
  dev_twin_function_arns = [
    for f in [
      "tenant-account", "create-location", "get-menu", "manage-menu", "pre-signed-url",
      "manage-layout-element", "publish-layout", "list-layout-version", "activate-layout-version",
      "google-business-api", "phone-agent", "catering-settings", "catering-discount-tiers",
      "gift-cards", "waitlist", "events-tickets",
    ] : "arn:aws:lambda:eu-north-1:123456789012:function:dev-${f}:live"
  ]
}

run "dev_inline_policies_fit_the_role_limit" {
  command = plan

  assert {
    condition = sum([for p in concat(
      [
        aws_iam_role_policy.tenant_table, aws_iam_role_policy.location_table,
        aws_iam_role_policy.user_table, aws_iam_role_policy.cognito,
        aws_iam_role_policy.start_workflows, aws_iam_role_policy.describe_workflows,
        aws_iam_role_policy.stripe_secret, aws_iam_role_policy.logs,
        aws_iam_role_policy.ses, aws_iam_role_policy.self_invoke,
        aws_iam_role_policy.finance, aws_iam_role_policy.site_repo,
        aws_iam_role_policy.print_table, aws_iam_role_policy.users_tab,
      ],
      aws_iam_role_policy.mail_outbox,
      aws_iam_role_policy.domains,
    ) : length(p.policy)]) < 9500
    error_message = "This role's own inline policies are near IAM's 10,240-character per-role limit (feature-hooks and site-analytics add about 700): move a policy to a managed one, as dev-twins is"
  }

  assert {
    condition     = length(aws_iam_role_policy.mail_outbox) == 1 && length(aws_iam_role_policy.domains) == 1
    error_message = "The dev run must include the outbox and domains policies, or the size check above measures too little"
  }

  assert {
    condition     = length(aws_iam_policy.dev_twins) == 1 && length(aws_iam_role_policy_attachment.dev_twins) == 1
    error_message = "Dev must get the dev twin grant as one managed policy attached to the role"
  }

  assert {
    condition     = length(aws_iam_policy.dev_twins[0].policy) < 6144
    error_message = "The dev-twins managed policy must stay under IAM's 6,144-character managed policy limit"
  }

  assert {
    condition     = jsondecode(aws_iam_policy.dev_twins[0].policy).Statement[0].Action == "lambda:InvokeFunction" && length(jsondecode(aws_iam_policy.dev_twins[0].policy).Statement[0].Resource) == 16
    error_message = "The dev-twins policy must allow only lambda:InvokeFunction on exactly the allowlisted aliases"
  }
}

run "prod_gets_no_dev_twin_or_outbox_grant" {
  command = plan

  # Same non-empty allowlist and outbox flag as dev on purpose: the module
  # itself must refuse them in prod, not only config.tf.
  variables {
    environment = "prod"
  }

  assert {
    condition     = length(aws_iam_policy.dev_twins) == 0 && length(aws_iam_role_policy_attachment.dev_twins) == 0
    error_message = "Prod must never get the dev twin grant"
  }

  assert {
    condition     = length(aws_iam_role_policy.mail_outbox) == 0
    error_message = "Prod must never get mail outbox access"
  }
}

run "dev_without_allowlist_gets_no_grant" {
  command = plan

  variables {
    dev_twin_function_arns = []
  }

  assert {
    condition     = length(aws_iam_policy.dev_twins) == 0 && length(aws_iam_role_policy_attachment.dev_twins) == 0
    error_message = "An empty allowlist must create no dev twin policy"
  }
}
