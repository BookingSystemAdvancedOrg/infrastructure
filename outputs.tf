output "stripe_webhook_urls" {
  description = "Webhook URLs Terraform registered with Stripe for this environment (informational - nothing to copy into the Stripe Dashboard anymore)"
  value = {
    reservation = module.stripe_webhooks.reservation_webhook_url
    order       = module.stripe_webhooks.order_webhook_url
    catering    = module.stripe_webhooks.catering_webhook_url
    platform    = module.platform_stripe_webhook_fn.function_url
  }
}

output "catering_signing_webhook_url" {
  description = "Webhook URL to register with the BankID signing provider (Scrive / Idura / Signicat) for catering signing callbacks"
  value       = local.catering_signing_webhook_url
}

output "api_endpoint" {
  description = "Base invoke URL of the HTTP API - what the front-end calls; also carries the BankID signing callback route (Stripe webhooks go to Lambda Function URLs instead)"
  value       = module.api_gateway.api_endpoint
}

output "customer_site_domain" {
  description = "Default *.cloudfront.net domain the customer-facing site is reachable at until a custom domain is wired up"
  value       = module.cloudfront_public.distribution_domain_name
}

output "admin_site_domain" {
  description = "Default *.cloudfront.net domain of the shared restaurant admin app (owners/staff of every tenant) - app.<platform domain> once that is set"
  value       = module.cloudfront_private.distribution_domain_name
}

# Read by CI (reusable_cicd.yml, "Deploy placeholder front-end" step) to
# sync a placeholder site into each bucket right after infra is applied, so
# the CloudFront distribution can be confirmed working before either
# front-end repo's own pipeline pushes a real build here.
output "customer_front_end_bucket_name" {
  description = "Name of the customer front-end asset S3 bucket"
  value       = module.customer_front_end_asset.bucket_name
}

output "admin_front_end_bucket_name" {
  description = "Name of the admin front-end asset S3 bucket"
  value       = module.admin_front_end_asset.bucket_name
}

output "customer_cloudfront_distribution_id" {
  description = "ID of the public CloudFront distribution - used by CI to invalidate the cache after syncing new content to the customer bucket"
  value       = module.cloudfront_public.distribution_id
}

output "admin_cloudfront_distribution_id" {
  description = "ID of the private CloudFront distribution - used by CI to invalidate the cache after syncing new content to the admin bucket"
  value       = module.cloudfront_private.distribution_id
}

# Function name -> ECR repository URL (no tag), for every Lambda container
# image repos. Read by the CI pipeline (reusable_cicd.yml) after the
# ECR-only targeted apply, to find any repository that doesn't have a
# ":latest" image yet and push a placeholder image to it before the full
# apply runs - `aws_lambda_function` with package_type = "Image" fails to
# create if no image exists at the referenced tag yet.
#
# NOTE: if you add a new Lambda function, add its ECR module's output to
# the ecr_repository_urls map below. That's the only manual step left: the
# CI bootstrap derives its -target list from config.tf automatically, and
# fails the build with a pointed error if this map is missing an entry.
output "ecr_repository_urls" {
  description = "Map of function name to ECR repository URL, used by CI to bootstrap placeholder images into newly created repositories"
  sensitive   = true
  value = {
    activate_layout_version    = module.activate_layout_version_ecr.activate_layout_version_ecr_repository_url
    block_table                = module.block_table_ecr.block_table_ecr_repository_url
    cancel_reservation         = module.cancel_reservation_ecr.cancel_reservation_ecr_repository_url
    create_location            = module.create_location_ecr.create_location_ecr_repository_url
    create_pending_reservation = module.create_pending_reservation_ecr.create_pending_reservation_ecr_repository_url
    expire_layout_version      = module.expire_layout_version_ecr.expire_layout_version_ecr_repository_url
    get_availability           = module.get_availability_ecr.get_availability_ecr_repository_url
    get_location               = module.get_location_ecr.get_location_ecr_repository_url
    get_menu                   = module.get_menu_ecr.get_menu_ecr_repository_url
    get_order                  = module.get_order_ecr.get_order_ecr_repository_url
    get_reservation            = module.get_reservation_ecr.get_reservation_ecr_repository_url
    list_layout_version        = module.list_layout_version_ecr.list_layout_version_ecr_repository_url
    manage_auth                = module.manage_auth_ecr.manage_auth_ecr_repository_url
    manage_layout_element      = module.manage_layout_element_ecr.manage_layout_element_ecr_repository_url
    manage_menu                = module.manage_menu_ecr.manage_menu_ecr_repository_url
    manage_order               = module.manage_order_ecr.manage_order_ecr_repository_url
    manage_user                = module.manage_user_ecr.manage_user_ecr_repository_url
    mark_arrived               = module.mark_arrived_ecr.mark_arrived_ecr_repository_url
    no_show_check              = module.no_show_check_ecr.no_show_check_ecr_repository_url
    notification               = module.notification_ecr.notification_ecr_repository_url
    payment_intent             = module.payment_intent_ecr.payment_intent_ecr_repository_url
    pre_signed_url             = module.pre_signed_url_ecr.pre_signed_url_ecr_repository_url
    publish_layout             = module.publish_layout_ecr.publish_layout_ecr_repository_url
    stripe_webhook             = module.stripe_webhook_ecr.stripe_webhook_ecr_repository_url
    catering_discount_tiers    = module.catering_discount_tiers_ecr.catering_discount_tiers_ecr_repository_url
    catering_requests          = module.catering_requests_ecr.catering_requests_ecr_repository_url
    catering_settings          = module.catering_settings_ecr.catering_settings_ecr_repository_url
    webhook_payment_intent     = module.webhook_payment_intent_ecr.webhook_payment_intent_ecr_repository_url
    reactivate_menu_item       = module.reactivate_menu_item_ecr.reactivate_menu_item_ecr_repository_url
    catering_offer             = module.catering_offer_ecr.catering_offer_ecr_repository_url
    catering_customer          = module.catering_customer_ecr.catering_customer_ecr_repository_url
    catering_signing_webhook   = module.catering_signing_webhook_ecr.catering_signing_webhook_ecr_repository_url
    catering_stripe_webhook    = module.catering_stripe_webhook_ecr.catering_stripe_webhook_ecr_repository_url
    catering_document          = module.catering_document_ecr.catering_document_ecr_repository_url
    catering_lifecycle         = module.catering_lifecycle_ecr.catering_lifecycle_ecr_repository_url
    dlq_replay                 = module.dlq_replay_ecr.dlq_replay_ecr_repository_url
    platform_tenants           = module.platform_tenants_ecr.platform_tenants_ecr_repository_url
    tenant_account             = module.tenant_account_ecr.tenant_account_ecr_repository_url
    tenant_site_config         = module.tenant_site_config_ecr.tenant_site_config_ecr_repository_url
    reservation_reminders      = module.reservation_reminders_ecr.reservation_reminders_ecr_repository_url
    platform_stripe_webhook    = module.platform_stripe_webhook_ecr.platform_stripe_webhook_ecr_repository_url
  }
}

# --- SaaS control plane ------------------------------------------------------------

output "admin_app_url" {
  description = "URL of the shared restaurant admin app every tenant's owners and staff sign in to"
  value       = local.admin_app_url
}

output "platform_admin_app_url" {
  description = "URL of the platform admin (operator) app - where you create and manage tenants"
  value       = local.platform_admin_app_url
}

output "platform_operator_login" {
  description = "What the platform admin app needs to sign operators in (Cognito hosted login, authorization code + PKCE, MFA enforced)"
  value = {
    user_pool_id     = module.cognito_platform.user_pool_id
    client_id        = module.cognito_platform.client_id
    hosted_login_url = module.cognito_platform.hosted_login_url
    scope            = module.cognito_platform.admin_scope
  }
}

output "tenant_workflow_arns" {
  description = "Step Functions state machines the platform API starts (onboarding, custom domains, offboarding)"
  value = {
    onboarding    = module.tenant_workflows.onboarding_state_machine_arn
    domain_attach = module.tenant_workflows.domain_attach_state_machine_arn
    domain_detach = module.tenant_workflows.domain_detach_state_machine_arn
    offboarding   = module.tenant_workflows.offboarding_state_machine_arn
  }
}

output "platform_domain_name_servers" {
  description = "Delegate var.platform_domain to these name servers (NS records at the registrar or parent zone). Empty while platform_domain is unset."
  value       = local.platform_domain_enabled ? module.platform_domain[0].name_servers : []
}

output "tenant_domain_cname_target" {
  description = "What a customer points their own domain's CNAME at (e.g. www.restaurang.se CNAME <this>). Empty while platform_domain is unset."
  value       = local.tenant_domain_cname_target
}

output "tenant_sites_bucket_name" {
  description = "Bucket tenant websites are published to, one <tenantId>/ prefix each. Empty while platform_domain is unset."
  value       = local.platform_domain_enabled ? module.platform_domain[0].sites_bucket_name : ""
}

output "tenant_sites_deploy_role_arn" {
  description = "Role the tenant website repos (var.tenant_site_repo_pattern) assume to publish. Empty while platform_domain is unset."
  value       = local.platform_domain_enabled ? module.tenant_sites_deploy_role[0].role_arn : ""
}

# Read by CI to deploy the placeholder operator app (same pattern as the two
# front-ends above).
output "platform_admin_front_end_bucket_name" {
  description = "Name of the platform admin (operator app) front-end asset S3 bucket"
  value       = module.platform_admin_front_end_asset.bucket_name
}

output "platform_admin_cloudfront_distribution_id" {
  description = "ID of the platform admin CloudFront distribution - used by CI to invalidate after deploying"
  value       = module.cloudfront_platform_admin.distribution_id
}

# Everything the sbs-admin repo's GitHub environments (dev / prod) need as
# variables - see the sbs-admin README, "Deploy". None of it is secret.
#   tofu output -json sbs_admin_deploy
output "sbs_admin_deploy" {
  description = "GitHub environment variables for the sbs-admin repo (operator console web app + platform-tenants Lambda)"
  value = {
    AWS_REGION                 = var.aws_region
    AWS_ROLE_ARN               = nonsensitive(module.platform_admin_front_end_role.role_arn)
    WEB_BUCKET                 = module.platform_admin_front_end_asset.bucket_name
    CLOUDFRONT_DISTRIBUTION_ID = module.cloudfront_platform_admin.distribution_id
    ECR_REPOSITORY             = module.platform_tenants_ecr.platform_tenants_ecr_repository_name
    LAMBDA_FUNCTION_NAME       = module.platform_tenants_fn.function_name
    VITE_API_URL               = module.api_gateway.api_endpoint
    VITE_COGNITO_AUTHORITY     = "https://cognito-idp.${var.aws_region}.amazonaws.com/${module.cognito_platform.user_pool_id}"
    VITE_COGNITO_CLIENT_ID     = module.cognito_platform.client_id
    VITE_COGNITO_DOMAIN        = module.cognito_platform.hosted_login_url
    VITE_PLATFORM_DOMAIN       = var.platform_domain
    CODEDEPLOY_APP             = module.lambda_releases.app_name
    ALERT_TOPIC_ARN            = module.alerts.topic_arn
  }
}

# Read by the release step in reusable_cicd.yml and by the app repos'
# pipelines (ci/lambda-release.sh): where releases run and where their
# results are emailed.
output "lambda_releases" {
  description = "CodeDeploy application, deployment groups (function name => group) and the alerts topic for release emails"
  value = {
    app_name          = module.lambda_releases.app_name
    alert_topic_arn   = module.alerts.topic_arn
    deployment_groups = module.lambda_releases.deployment_group_names
  }
}

# Publish these at the sender domain's DNS provider (once per AWS account)
# so SES can DKIM-sign and send from the no-reply address.
output "ses_dkim_records" {
  description = "DKIM CNAME records for the SES sender domain"
  value       = module.ses.dkim_records
}
