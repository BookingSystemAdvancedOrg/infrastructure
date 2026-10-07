
terraform {
  required_version = ">=1.14.0, < 2.0.0"
  backend "s3" {}

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    stripe = {
      source  = "lukasaron/stripe"
      version = "~> 3.0"
    }
    # Zips the infra-owned Lambdas that ship from this repo
    # (compute/lambda/pre-token-generation)
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.7"
    }
  }
}

# Primary provider — all resources deploy to Stockholm (eu-north-1) for GDPR data residency
provider "aws" {
  region = var.aws_region
}

# ACM certificates for CloudFront MUST be in us-east-1 — AWS hard requirement
# Only the acm module uses this alias via providers = { aws = aws.us_east_1 }
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
}

# Talks to the Stripe account this environment deploys against - the same
# sk_ key the payment Lambdas use decides whether that's test mode (dev) or
# live mode (prod). Only used by payments/stripe: webhook endpoints and the
# catering tax rates.
provider "stripe" {
  api_key = var.stripe_secret_key
}


#DynamoDB Tables
module "live_layout_element" {
  source      = "./storage/dynamodb/live-layout-element"
  environment = var.env
}
module "location" {
  source      = "./storage/dynamodb/location"
  environment = var.env
}
module "menu" {
  source      = "./storage/dynamodb/menu"
  environment = var.env
}
module "published_layout_snapshot" {
  source      = "./storage/dynamodb/published-layout-snapshot"
  environment = var.env
}
module "reservation" {
  source                  = "./storage/dynamodb/reservation"
  environment             = var.env
  notification_lambda_arn = module.notification_fn.alias_arn
  notification_dlq_arn    = module.dead_letter.notification_stream_dlq_arn
}
module "slot_occupancy" {
  source      = "./storage/dynamodb/slot-occupancy"
  environment = var.env
}
module "user" {
  source      = "./storage/dynamodb/user"
  environment = var.env
}
module "payment_delinquency" {
  source      = "./storage/dynamodb/payment-delinquency"
  environment = var.env
}
module "order" {
  source                  = "./storage/dynamodb/order"
  environment             = var.env
  notification_lambda_arn = module.notification_fn.alias_arn
  notification_dlq_arn    = module.dead_letter.notification_stream_dlq_arn
}
module "catering_discount_tiers" {
  source      = "./storage/dynamodb/catering-discount-tiers"
  environment = var.env
}
module "catering_requests" {
  source                  = "./storage/dynamodb/catering-requests"
  environment             = var.env
  notification_lambda_arn = module.notification_fn.alias_arn
  notification_dlq_arn    = module.dead_letter.notification_stream_dlq_arn
  lifecycle_lambda_arn    = module.catering_lifecycle_fn.alias_arn
  lifecycle_dlq_arn       = module.dead_letter.lifecycle_stream_dlq_arn
}
module "catering_request_history" {
  source      = "./storage/dynamodb/catering-request-history"
  environment = var.env
}
# Control plane: tenants, their domains/plan/Stripe account, plan catalog
module "tenant" {
  source      = "./storage/dynamodb/tenant"
  environment = var.env
  plans       = var.plans
}

#SQS (dead-letter queues)
module "dead_letter" {
  source      = "./storage/sqs/dead-letter"
  environment = var.env
}


#Secrets
module "catering_secrets" {
  source      = "./security/secrets/catering"
  environment = var.env
}
# Platform Stripe key (Connect platform account) - the only Stripe key in the stack
module "platform_secrets" {
  source            = "./security/secrets/platform"
  environment       = var.env
  stripe_secret_key = var.stripe_secret_key
}


#S3 Buckets
module "menu_image" {
  source                                  = "./storage/s3/menu-image"
  environment                             = var.env
  public_cloudfront_distribution_arn      = module.cloudfront_public.distribution_arn
  private_cloudfront_distribution_arn     = module.cloudfront_private.distribution_arn
  additional_cloudfront_distribution_arns = local.platform_domain_enabled ? [module.platform_domain[0].multitenant_distribution_arn] : []
  allowed_origins = distinct([
    "https://${module.cloudfront_public.distribution_domain_name}",
    "https://${module.cloudfront_private.distribution_domain_name}",
    local.admin_app_url, # app.<platform domain> once set - presigned uploads come from there
  ])
}
module "customer_front_end_asset" {
  source                      = "./storage/s3/customer-front-end-asset"
  environment                 = var.env
  cloudfront_distribution_arn = module.cloudfront_public.distribution_arn
}
module "catering_documents" {
  source      = "./storage/s3/catering-documents"
  environment = var.env
}
module "admin_front_end_asset" {
  source                      = "./storage/s3/admin-front-end-asset"
  environment                 = var.env
  cloudfront_distribution_arn = module.cloudfront_private.distribution_arn
}
module "platform_admin_front_end_asset" {
  source                      = "./storage/s3/platform-admin-front-end-asset"
  environment                 = var.env
  cloudfront_distribution_arn = module.cloudfront_platform_admin.distribution_arn
}


#Cognito
# Tenant pool - every restaurant's owners and staff (tenant_id claim in every token)
module "cognito" {
  source                             = "./storage/cognito"
  environment                        = var.env
  pre_token_generation_lambda_arn    = module.pre_token_generation_fn.alias_arn
  pre_token_generation_function_name = module.pre_token_generation_fn.function_name
  admin_app_url                      = local.admin_app_url
  invites_via_ses                    = var.cognito_invites_via_ses
  ses_identity_arn                   = local.ses_identity_arn
  invite_from_address                = local.no_reply_from_address
}
# Operator pool - you; the only tokens /platform/* accepts
module "cognito_platform" {
  source          = "./storage/cognito-platform"
  environment     = var.env
  operator_emails = var.platform_operator_emails
  app_urls        = local.platform_admin_app_urls
}


#Network
module "ses" {
  source                 = "./network/ses"
  no_reply_email_address = var.no_reply_email_address
}


#IAM Security
module "pre_token_generation_role" {
  source      = "./security/iam/pre-token-generation"
  environment = var.env
  region      = var.aws_region
}
module "get_menu_role" {
  source         = "./security/iam/get-menu"
  environment    = var.env
  menu_table_arn = module.menu.table_arn
  region         = var.aws_region
}
module "manage_menu_role" {
  source                    = "./security/iam/manage-menu"
  environment               = var.env
  menu_table_arn            = module.menu.table_arn
  scheduler_invoke_role_arn = module.scheduler_invoke_reactivate_menu_item_role.role_arn
  region                    = var.aws_region
}
module "manage_order_role" {
  source          = "./security/iam/manage-order"
  environment     = var.env
  order_table_arn = module.order.table_arn
  region          = var.aws_region
}
module "manage_user_role" {
  source         = "./security/iam/manage-user"
  environment    = var.env
  user_table_arn = module.user.table_arn
  user_pool_arn  = module.cognito.user_pool_arn
  region         = var.aws_region
}
module "get_reservation_role" {
  source                = "./security/iam/get-reservation"
  environment           = var.env
  reservation_table_arn = module.reservation.table_arn
  region                = var.aws_region
}
module "get_order_role" {
  source          = "./security/iam/get-order"
  environment     = var.env
  order_table_arn = module.order.table_arn
  region          = var.aws_region
}
module "payment_intent_role" {
  source            = "./security/iam/payment-intent"
  environment       = var.env
  order_table_arn   = module.order.table_arn
  region            = var.aws_region
  stripe_secret_arn = module.platform_secrets.stripe_secret_arn
}
module "mark_arrived_role" {
  source                = "./security/iam/mark-arrived"
  environment           = var.env
  reservation_table_arn = module.reservation.table_arn
  region                = var.aws_region
}
module "create_location_role" {
  source             = "./security/iam/create-location"
  environment        = var.env
  location_table_arn = module.location.table_arn
  tenant_table_arn   = module.tenant.table_arn
  region             = var.aws_region
}
module "manage_layout_element_role" {
  source                        = "./security/iam/manage-layout-element"
  environment                   = var.env
  live_layout_element_table_arn = module.live_layout_element.table_arn
  region                        = var.aws_region
}
module "publish_layout_role" {
  source                              = "./security/iam/publish-layout"
  environment                         = var.env
  live_layout_element_table_arn       = module.live_layout_element.table_arn
  published_layout_snapshot_table_arn = module.published_layout_snapshot.table_arn
  region                              = var.aws_region
}
module "list_layout_version_role" {
  source                              = "./security/iam/list-layout-version"
  environment                         = var.env
  published_layout_snapshot_table_arn = module.published_layout_snapshot.table_arn
  region                              = var.aws_region
}
module "scheduler_invoke_expire_layout_version_role" {
  source                           = "./security/iam/scheduler-invoke-expire-layout-version"
  environment                      = var.env
  expire_layout_version_lambda_arn = module.expire_layout_version_fn.function_arn
}
module "activate_layout_version_role" {
  source                              = "./security/iam/activate-layout-version"
  environment                         = var.env
  published_layout_snapshot_table_arn = module.published_layout_snapshot.table_arn
  scheduler_invoke_role_arn           = module.scheduler_invoke_expire_layout_version_role.role_arn
  region                              = var.aws_region
}
module "expire_layout_version_role" {
  source                              = "./security/iam/expire-layout-version"
  environment                         = var.env
  published_layout_snapshot_table_arn = module.published_layout_snapshot.table_arn
  region                              = var.aws_region
  scheduled_invocation_dlq_arn        = module.dead_letter.scheduled_invocation_dlq_arn
}
module "scheduler_invoke_reactivate_menu_item_role" {
  source                          = "./security/iam/scheduler-invoke-reactivate-menu-item"
  environment                     = var.env
  reactivate_menu_item_lambda_arn = module.reactivate_menu_item_fn.function_arn
}
module "reactivate_menu_item_role" {
  source                       = "./security/iam/reactivate-menu-item"
  environment                  = var.env
  menu_table_arn               = module.menu.table_arn
  region                       = var.aws_region
  scheduled_invocation_dlq_arn = module.dead_letter.scheduled_invocation_dlq_arn
}
module "get_location_role" {
  source             = "./security/iam/get-location"
  environment        = var.env
  location_table_arn = module.location.table_arn
  region             = var.aws_region
}
module "get_availability_role" {
  source                              = "./security/iam/get-availability"
  environment                         = var.env
  location_table_arn                  = module.location.table_arn
  slot_occupancy_table_arn            = module.slot_occupancy.table_arn
  published_layout_snapshot_table_arn = module.published_layout_snapshot.table_arn
  region                              = var.aws_region
}
module "create_pending_reservation_role" {
  source                              = "./security/iam/create-pending-reservation"
  environment                         = var.env
  location_table_arn                  = module.location.table_arn
  published_layout_snapshot_table_arn = module.published_layout_snapshot.table_arn
  slot_occupancy_table_arn            = module.slot_occupancy.table_arn
  reservation_table_arn               = module.reservation.table_arn
  payment_delinquency_table_arn       = module.payment_delinquency.table_arn
  region                              = var.aws_region
  stripe_secret_arn                   = module.platform_secrets.stripe_secret_arn
}
module "scheduler_invoke_no_show_check_role" {
  source                   = "./security/iam/scheduler-invoke-no-show-check"
  environment              = var.env
  no_show_check_lambda_arn = module.no_show_check_fn.function_arn
}
module "no_show_check_role" {
  source                        = "./security/iam/no-show-check"
  environment                   = var.env
  location_table_arn            = module.location.table_arn
  slot_occupancy_table_arn      = module.slot_occupancy.table_arn
  reservation_table_arn         = module.reservation.table_arn
  payment_delinquency_table_arn = module.payment_delinquency.table_arn
  region                        = var.aws_region
  scheduled_invocation_dlq_arn  = module.dead_letter.scheduled_invocation_dlq_arn
}
module "cancel_reservation_role" {
  source                   = "./security/iam/cancel-reservation"
  environment              = var.env
  location_table_arn       = module.location.table_arn
  slot_occupancy_table_arn = module.slot_occupancy.table_arn
  reservation_table_arn    = module.reservation.table_arn
  region                   = var.aws_region
  stripe_secret_arn        = module.platform_secrets.stripe_secret_arn
}
module "pre_signed_url_role" {
  source                 = "./security/iam/pre-signed-url"
  environment            = var.env
  menu_images_bucket_arn = module.menu_image.bucket_arn
  region                 = var.aws_region
}
module "manage_auth_role" {
  source        = "./security/iam/manage-auth"
  environment   = var.env
  user_pool_arn = module.cognito.user_pool_arn
  region        = var.aws_region
}
module "stripe_webhook_role" {
  source                        = "./security/iam/stripe-webhook"
  environment                   = var.env
  location_table_arn            = module.location.table_arn
  reservation_table_arn         = module.reservation.table_arn
  payment_delinquency_table_arn = module.payment_delinquency.table_arn
  scheduler_invoke_role_arn     = module.scheduler_invoke_no_show_check_role.role_arn
  webhook_secret_arn            = module.stripe_webhooks.reservation_webhook_secret_arn
  region                        = var.aws_region
}
module "webhook_payment_intent_role" {
  source             = "./security/iam/webhook-payment-intent"
  environment        = var.env
  order_table_arn    = module.order.table_arn
  webhook_secret_arn = module.stripe_webhooks.order_webhook_secret_arn
  region             = var.aws_region
}
module "block_table_role" {
  source                              = "./security/iam/block-table"
  environment                         = var.env
  location_table_arn                  = module.location.table_arn
  user_table_arn                      = module.user.table_arn
  slot_occupancy_table_arn            = module.slot_occupancy.table_arn
  published_layout_snapshot_table_arn = module.published_layout_snapshot.table_arn
  region                              = var.aws_region
}
module "notification_role" {
  source                       = "./security/iam/notification"
  environment                  = var.env
  reservation_stream_arn       = module.reservation.stream_arn
  order_stream_arn             = module.order.stream_arn
  catering_requests_stream_arn = module.catering_requests.stream_arn
  ses_identity_arn             = local.ses_identity_arn
  region                       = var.aws_region

  notification_dlq_arn                 = module.dead_letter.notification_stream_dlq_arn
  catering_link_signing_key_secret_arn = module.catering_secrets.link_signing_key_secret_arn
}
module "catering_settings_role" {
  source             = "./security/iam/catering-settings"
  environment        = var.env
  location_table_arn = module.location.table_arn
  region             = var.aws_region
}
module "catering_discount_tiers_role" {
  source                            = "./security/iam/catering-discount-tiers"
  environment                       = var.env
  catering_discount_tiers_table_arn = module.catering_discount_tiers.table_arn
  region                            = var.aws_region
}
module "catering_requests_role" {
  source                             = "./security/iam/catering-requests"
  environment                        = var.env
  catering_requests_table_arn        = module.catering_requests.table_arn
  catering_request_history_table_arn = module.catering_request_history.table_arn
  location_table_arn                 = module.location.table_arn
  catering_discount_tiers_table_arn  = module.catering_discount_tiers.table_arn
  menu_table_arn                     = module.menu.table_arn
  turnstile_secret_arn               = module.catering_secrets.turnstile_secret_arn
  link_signing_key_secret_arn        = module.catering_secrets.link_signing_key_secret_arn
  region                             = var.aws_region
}
module "catering_offer_role" {
  source                             = "./security/iam/catering-offer"
  environment                        = var.env
  catering_requests_table_arn        = module.catering_requests.table_arn
  catering_request_history_table_arn = module.catering_request_history.table_arn
  location_table_arn                 = module.location.table_arn
  menu_table_arn                     = module.menu.table_arn
  catering_documents_bucket_arn      = module.catering_documents.bucket_arn
  stripe_secret_arn                  = module.platform_secrets.stripe_secret_arn
  document_function_arn              = module.catering_document_fn.function_arn
  region                             = var.aws_region
}
module "catering_customer_role" {
  source                             = "./security/iam/catering-customer"
  environment                        = var.env
  catering_requests_table_arn        = module.catering_requests.table_arn
  catering_request_history_table_arn = module.catering_request_history.table_arn
  location_table_arn                 = module.location.table_arn
  catering_documents_bucket_arn      = module.catering_documents.bucket_arn
  link_signing_key_secret_arn        = module.catering_secrets.link_signing_key_secret_arn
  signing_provider_secret_arn        = module.catering_secrets.signing_provider_secret_arn
  stripe_secret_arn                  = module.platform_secrets.stripe_secret_arn
  region                             = var.aws_region
}
module "catering_signing_webhook_role" {
  source                             = "./security/iam/catering-signing-webhook"
  environment                        = var.env
  catering_requests_table_arn        = module.catering_requests.table_arn
  catering_request_history_table_arn = module.catering_request_history.table_arn
  catering_documents_bucket_arn      = module.catering_documents.bucket_arn
  signing_provider_secret_arn        = module.catering_secrets.signing_provider_secret_arn
  region                             = var.aws_region
}
module "catering_stripe_webhook_role" {
  source                             = "./security/iam/catering-stripe-webhook"
  environment                        = var.env
  catering_requests_table_arn        = module.catering_requests.table_arn
  catering_request_history_table_arn = module.catering_request_history.table_arn
  catering_documents_bucket_arn      = module.catering_documents.bucket_arn
  stripe_secret_arn                  = module.platform_secrets.stripe_secret_arn
  webhook_secret_arn                 = module.stripe_webhooks.catering_webhook_secret_arn
  region                             = var.aws_region
}
module "catering_document_role" {
  source                             = "./security/iam/catering-document"
  environment                        = var.env
  catering_request_history_table_arn = module.catering_request_history.table_arn
  location_table_arn                 = module.location.table_arn
  catering_documents_bucket_arn      = module.catering_documents.bucket_arn
  region                             = var.aws_region
}
module "catering_lifecycle_role" {
  source                             = "./security/iam/catering-lifecycle"
  environment                        = var.env
  catering_requests_stream_arn       = module.catering_requests.stream_arn
  lifecycle_stream_dlq_arn           = module.dead_letter.lifecycle_stream_dlq_arn
  catering_requests_table_arn        = module.catering_requests.table_arn
  catering_request_history_table_arn = module.catering_request_history.table_arn
  location_table_arn                 = module.location.table_arn
  stripe_secret_arn                  = module.platform_secrets.stripe_secret_arn
  schedule_group_name                = module.scheduler_invoke_catering_lifecycle_role.schedule_group_name
  scheduler_invoke_role_arn          = module.scheduler_invoke_catering_lifecycle_role.role_arn
  region                             = var.aws_region
  scheduled_invocation_dlq_arn       = module.dead_letter.scheduled_invocation_dlq_arn
}
module "dlq_replay_role" {
  source                             = "./security/iam/dlq-replay"
  environment                        = var.env
  lifecycle_stream_dlq_arn           = module.dead_letter.lifecycle_stream_dlq_arn
  notification_stream_dlq_arn        = module.dead_letter.notification_stream_dlq_arn
  scheduled_invocation_dlq_arn       = module.dead_letter.scheduled_invocation_dlq_arn
  catering_lifecycle_function_arn    = module.catering_lifecycle_fn.function_arn
  notification_function_arn          = module.notification_fn.function_arn
  no_show_check_function_arn         = module.no_show_check_fn.function_arn
  reactivate_menu_item_function_arn  = module.reactivate_menu_item_fn.function_arn
  expire_layout_version_function_arn = module.expire_layout_version_fn.function_arn
  catering_requests_stream_arn       = module.catering_requests.stream_arn
  reservation_stream_arn             = module.reservation.stream_arn
  order_stream_arn                   = module.order.stream_arn
  alert_topic_arn                    = module.alerts.topic_arn
  region                             = var.aws_region
}
module "scheduler_invoke_dlq_replay_role" {
  source                = "./security/iam/scheduler-invoke-dlq-replay"
  environment           = var.env
  dlq_replay_lambda_arn = module.dlq_replay_fn.function_arn
}
module "scheduler_invoke_catering_lifecycle_role" {
  source                        = "./security/iam/scheduler-invoke-catering-lifecycle"
  environment                   = var.env
  catering_lifecycle_lambda_arn = module.catering_lifecycle_fn.function_arn
  scheduler_dlq_arn             = module.dead_letter.scheduled_invocation_dlq_arn
}

# --- Platform / tenant control plane Lambdas -----------------------------------
module "platform_tenants_role" {
  source                          = "./security/iam/platform-tenants"
  environment                     = var.env
  tenant_table_arn                = module.tenant.table_arn
  location_table_arn              = module.location.table_arn
  user_table_arn                  = module.user.table_arn
  tenant_user_pool_arn            = module.cognito.user_pool_arn
  onboarding_state_machine_arn    = module.tenant_workflows.onboarding_state_machine_arn
  domain_attach_state_machine_arn = module.tenant_workflows.domain_attach_state_machine_arn
  domain_detach_state_machine_arn = module.tenant_workflows.domain_detach_state_machine_arn
  offboarding_state_machine_arn   = module.tenant_workflows.offboarding_state_machine_arn
  stripe_secret_arn               = module.platform_secrets.stripe_secret_arn
  region                          = var.aws_region
}
module "tenant_account_role" {
  source             = "./security/iam/tenant-account"
  environment        = var.env
  tenant_table_arn   = module.tenant.table_arn
  location_table_arn = module.location.table_arn
  stripe_secret_arn  = module.platform_secrets.stripe_secret_arn
  region             = var.aws_region
}
module "tenant_site_config_role" {
  source             = "./security/iam/tenant-site-config"
  environment        = var.env
  location_table_arn = module.location.table_arn
  region             = var.aws_region
}
module "platform_stripe_webhook_role" {
  source                     = "./security/iam/platform-stripe-webhook"
  environment                = var.env
  tenant_table_arn           = module.tenant.table_arn
  connect_webhook_secret_arn = module.stripe_webhooks.platform_connect_webhook_secret_arn
  billing_webhook_secret_arn = module.stripe_webhooks.platform_billing_webhook_secret_arn
  stripe_secret_arn          = module.platform_secrets.stripe_secret_arn
  region                     = var.aws_region
}

# Shared tenant-context read policy (tenant table + locationId index) on every
# application Lambda role - the input to each request's tenant check
module "tenant_context_policy" {
  source                 = "./security/iam/tenant-context"
  environment            = var.env
  tenant_table_arn       = module.tenant.table_arn
  location_table_arn     = module.location.table_arn
  location_id_index_name = module.location.location_id_index_name
  role_names             = local.tenant_aware_role_names
}

#ECR
module "activate_layout_version_ecr" {
  source      = "./storage/ecr/activate-layout-version"
  environment = var.env
}
module "expire_layout_version_ecr" {
  source      = "./storage/ecr/expire-layout-version"
  environment = var.env
}
module "reactivate_menu_item_ecr" {
  source      = "./storage/ecr/reactivate-menu-item"
  environment = var.env
}
module "block_table_ecr" {
  source      = "./storage/ecr/block-table"
  environment = var.env
}
module "cancel_reservation_ecr" {
  source      = "./storage/ecr/cancel-reservation"
  environment = var.env
}
module "create_location_ecr" {
  source      = "./storage/ecr/create-location"
  environment = var.env
}
module "create_pending_reservation_ecr" {
  source      = "./storage/ecr/create-pending-reservation"
  environment = var.env
}
module "get_availability_ecr" {
  source      = "./storage/ecr/get-availability"
  environment = var.env
}
module "get_location_ecr" {
  source      = "./storage/ecr/get-location"
  environment = var.env
}
module "get_menu_ecr" {
  source      = "./storage/ecr/get-menu"
  environment = var.env
}
module "get_reservation_ecr" {
  source      = "./storage/ecr/get-reservation"
  environment = var.env
}
module "get_order_ecr" {
  source      = "./storage/ecr/get-order"
  environment = var.env
}
module "payment_intent_ecr" {
  source      = "./storage/ecr/payment-intent"
  environment = var.env
}
module "list_layout_version_ecr" {
  source      = "./storage/ecr/list-layout-version"
  environment = var.env
}
module "manage_auth_ecr" {
  source      = "./storage/ecr/manage-auth"
  environment = var.env
}
module "manage_layout_element_ecr" {
  source      = "./storage/ecr/manage-layout-element"
  environment = var.env
}
module "manage_menu_ecr" {
  source      = "./storage/ecr/manage-menu"
  environment = var.env
}
module "manage_order_ecr" {
  source      = "./storage/ecr/manage-order"
  environment = var.env
}
module "manage_user_ecr" {
  source      = "./storage/ecr/manage-user"
  environment = var.env
}
module "mark_arrived_ecr" {
  source      = "./storage/ecr/mark-arrived"
  environment = var.env
}
module "no_show_check_ecr" {
  source      = "./storage/ecr/no-show-check"
  environment = var.env
}
module "notification_ecr" {
  source      = "./storage/ecr/notification"
  environment = var.env
}
module "pre_signed_url_ecr" {
  source      = "./storage/ecr/pre-signed-url"
  environment = var.env
}
module "publish_layout_ecr" {
  source      = "./storage/ecr/publish-layout"
  environment = var.env
}
module "stripe_webhook_ecr" {
  source      = "./storage/ecr/stripe-webhook"
  environment = var.env
}
module "webhook_payment_intent_ecr" {
  source      = "./storage/ecr/webhook-payment-intent"
  environment = var.env
}
module "catering_settings_ecr" {
  source      = "./storage/ecr/catering-settings"
  environment = var.env
}
module "catering_discount_tiers_ecr" {
  source      = "./storage/ecr/catering-discount-tiers"
  environment = var.env
}
module "catering_requests_ecr" {
  source      = "./storage/ecr/catering-requests"
  environment = var.env
}
module "catering_offer_ecr" {
  source      = "./storage/ecr/catering-offer"
  environment = var.env
}
module "catering_customer_ecr" {
  source      = "./storage/ecr/catering-customer"
  environment = var.env
}
module "catering_signing_webhook_ecr" {
  source      = "./storage/ecr/catering-signing-webhook"
  environment = var.env
}
module "catering_stripe_webhook_ecr" {
  source      = "./storage/ecr/catering-stripe-webhook"
  environment = var.env
}
module "catering_document_ecr" {
  source      = "./storage/ecr/catering-document"
  environment = var.env
}
module "dlq_replay_ecr" {
  source      = "./storage/ecr/dlq-replay"
  environment = var.env
}
module "catering_lifecycle_ecr" {
  source      = "./storage/ecr/catering-lifecycle"
  environment = var.env
}
module "platform_tenants_ecr" {
  source      = "./storage/ecr/platform-tenants"
  environment = var.env
}
module "tenant_account_ecr" {
  source      = "./storage/ecr/tenant-account"
  environment = var.env
}
module "tenant_site_config_ecr" {
  source      = "./storage/ecr/tenant-site-config"
  environment = var.env
}
module "platform_stripe_webhook_ecr" {
  source      = "./storage/ecr/platform-stripe-webhook"
  environment = var.env
}


#Compute
# Infra-owned zip Lambda (not an image): Cognito trigger, must never be a placeholder
module "pre_token_generation_fn" {
  source      = "./compute/lambda/pre-token-generation"
  environment = var.env
  role_arn    = module.pre_token_generation_role.role_arn
}
module "activate_layout_version_fn" {
  source                               = "./compute/lambda/activate-layout-version"
  environment                          = var.env
  role_arn                             = module.activate_layout_version_role.role_arn
  ecr_repository_url                   = module.activate_layout_version_ecr.activate_layout_version_ecr_repository_url
  published_layout_snapshot_table_name = module.published_layout_snapshot.table_name
  scheduler_invoke_role_arn            = module.scheduler_invoke_expire_layout_version_role.role_arn
  expire_layout_version_function_arn   = module.expire_layout_version_fn.alias_arn
  region                               = var.aws_region
  tenant_table_name                    = module.tenant.table_name
  location_table_name                  = module.location.table_name
  location_id_index_name               = module.location.location_id_index_name
}
module "expire_layout_version_fn" {
  source                               = "./compute/lambda/expire-layout-version"
  environment                          = var.env
  role_arn                             = module.expire_layout_version_role.role_arn
  ecr_repository_url                   = module.expire_layout_version_ecr.expire_layout_version_ecr_repository_url
  published_layout_snapshot_table_name = module.published_layout_snapshot.table_name
  region                               = var.aws_region
  failure_destination_arn              = module.dead_letter.scheduled_invocation_dlq_arn
  tenant_table_name                    = module.tenant.table_name
  location_table_name                  = module.location.table_name
  location_id_index_name               = module.location.location_id_index_name
}
module "reactivate_menu_item_fn" {
  source                  = "./compute/lambda/reactivate-menu-item"
  environment             = var.env
  role_arn                = module.reactivate_menu_item_role.role_arn
  ecr_repository_url      = module.reactivate_menu_item_ecr.reactivate_menu_item_ecr_repository_url
  menu_table_name         = module.menu.table_name
  region                  = var.aws_region
  failure_destination_arn = module.dead_letter.scheduled_invocation_dlq_arn
  tenant_table_name       = module.tenant.table_name
  location_table_name     = module.location.table_name
  location_id_index_name  = module.location.location_id_index_name
}
module "block_table_fn" {
  source                               = "./compute/lambda/block-table"
  environment                          = var.env
  role_arn                             = module.block_table_role.role_arn
  ecr_repository_url                   = module.block_table_ecr.block_table_ecr_repository_url
  location_table_name                  = module.location.table_name
  user_table_name                      = module.user.table_name
  slot_occupancy_table_name            = module.slot_occupancy.table_name
  published_layout_snapshot_table_name = module.published_layout_snapshot.table_name
  region                               = var.aws_region
  tenant_table_name                    = module.tenant.table_name
  location_id_index_name               = module.location.location_id_index_name
}
module "cancel_reservation_fn" {
  source                    = "./compute/lambda/cancel-reservation"
  environment               = var.env
  role_arn                  = module.cancel_reservation_role.role_arn
  ecr_repository_url        = module.cancel_reservation_ecr.cancel_reservation_ecr_repository_url
  location_table_name       = module.location.table_name
  slot_occupancy_table_name = module.slot_occupancy.table_name
  reservation_table_name    = module.reservation.table_name
  stripe_secret_arn         = module.platform_secrets.stripe_secret_arn
  region                    = var.aws_region
  tenant_table_name         = module.tenant.table_name
  location_id_index_name    = module.location.location_id_index_name
}
module "create_location_fn" {
  source                 = "./compute/lambda/create-location"
  environment            = var.env
  role_arn               = module.create_location_role.role_arn
  ecr_repository_url     = module.create_location_ecr.create_location_ecr_repository_url
  location_table_name    = module.location.table_name
  region                 = var.aws_region
  tenant_table_name      = module.tenant.table_name
  location_id_index_name = module.location.location_id_index_name
}
module "create_pending_reservation_fn" {
  source                               = "./compute/lambda/create-pending-reservation"
  environment                          = var.env
  role_arn                             = module.create_pending_reservation_role.role_arn
  ecr_repository_url                   = module.create_pending_reservation_ecr.create_pending_reservation_ecr_repository_url
  location_table_name                  = module.location.table_name
  published_layout_snapshot_table_name = module.published_layout_snapshot.table_name
  slot_occupancy_table_name            = module.slot_occupancy.table_name
  reservation_table_name               = module.reservation.table_name
  payment_delinquency_table_name       = module.payment_delinquency.table_name
  stripe_secret_arn                    = module.platform_secrets.stripe_secret_arn
  region                               = var.aws_region
  tenant_table_name                    = module.tenant.table_name
  location_id_index_name               = module.location.location_id_index_name
}
module "get_availability_fn" {
  source                               = "./compute/lambda/get-availability"
  environment                          = var.env
  role_arn                             = module.get_availability_role.role_arn
  ecr_repository_url                   = module.get_availability_ecr.get_availability_ecr_repository_url
  location_table_name                  = module.location.table_name
  slot_occupancy_table_name            = module.slot_occupancy.table_name
  published_layout_snapshot_table_name = module.published_layout_snapshot.table_name
  region                               = var.aws_region
  tenant_table_name                    = module.tenant.table_name
  location_id_index_name               = module.location.location_id_index_name
}
module "get_location_fn" {
  source                 = "./compute/lambda/get-location"
  environment            = var.env
  role_arn               = module.get_location_role.role_arn
  ecr_repository_url     = module.get_location_ecr.get_location_ecr_repository_url
  location_table_name    = module.location.table_name
  region                 = var.aws_region
  tenant_table_name      = module.tenant.table_name
  location_id_index_name = module.location.location_id_index_name
}
module "get_menu_fn" {
  source                 = "./compute/lambda/get-menu"
  environment            = var.env
  role_arn               = module.get_menu_role.role_arn
  ecr_repository_url     = module.get_menu_ecr.get_menu_ecr_repository_url
  menu_table_name        = module.menu.table_name
  region                 = var.aws_region
  tenant_table_name      = module.tenant.table_name
  location_table_name    = module.location.table_name
  location_id_index_name = module.location.location_id_index_name
}
module "get_reservation_fn" {
  source                 = "./compute/lambda/get-reservation"
  environment            = var.env
  role_arn               = module.get_reservation_role.role_arn
  ecr_repository_url     = module.get_reservation_ecr.get_reservation_ecr_repository_url
  reservation_table_name = module.reservation.table_name
  region                 = var.aws_region
  tenant_table_name      = module.tenant.table_name
  location_table_name    = module.location.table_name
  location_id_index_name = module.location.location_id_index_name
}
module "get_order_fn" {
  source                 = "./compute/lambda/get-order"
  environment            = var.env
  role_arn               = module.get_order_role.role_arn
  ecr_repository_url     = module.get_order_ecr.get_order_ecr_repository_url
  order_table_name       = module.order.table_name
  region                 = var.aws_region
  tenant_table_name      = module.tenant.table_name
  location_table_name    = module.location.table_name
  location_id_index_name = module.location.location_id_index_name
}
module "payment_intent_fn" {
  source                 = "./compute/lambda/payment-intent"
  environment            = var.env
  role_arn               = module.payment_intent_role.role_arn
  ecr_repository_url     = module.payment_intent_ecr.payment_intent_ecr_repository_url
  order_table_name       = module.order.table_name
  stripe_secret_arn      = module.platform_secrets.stripe_secret_arn
  region                 = var.aws_region
  tenant_table_name      = module.tenant.table_name
  location_table_name    = module.location.table_name
  location_id_index_name = module.location.location_id_index_name
}
module "list_layout_version_fn" {
  source                               = "./compute/lambda/list-layout-version"
  environment                          = var.env
  role_arn                             = module.list_layout_version_role.role_arn
  ecr_repository_url                   = module.list_layout_version_ecr.list_layout_version_ecr_repository_url
  published_layout_snapshot_table_name = module.published_layout_snapshot.table_name
  region                               = var.aws_region
  tenant_table_name                    = module.tenant.table_name
  location_table_name                  = module.location.table_name
  location_id_index_name               = module.location.location_id_index_name
}
module "manage_auth_fn" {
  source                = "./compute/lambda/manage-auth"
  environment           = var.env
  role_arn              = module.manage_auth_role.role_arn
  ecr_repository_url    = module.manage_auth_ecr.manage_auth_ecr_repository_url
  cognito_user_pool_id  = module.cognito.user_pool_id
  cognito_client_id     = module.cognito.user_pool_client_id
  cognito_client_secret = module.cognito.user_pool_client_secret
  region                = var.aws_region
}
module "manage_layout_element_fn" {
  source                         = "./compute/lambda/manage-layout-element"
  environment                    = var.env
  role_arn                       = module.manage_layout_element_role.role_arn
  ecr_repository_url             = module.manage_layout_element_ecr.manage_layout_element_ecr_repository_url
  live_layout_element_table_name = module.live_layout_element.table_name
  region                         = var.aws_region
  tenant_table_name              = module.tenant.table_name
  location_table_name            = module.location.table_name
  location_id_index_name         = module.location.location_id_index_name
}
module "manage_menu_fn" {
  source                            = "./compute/lambda/manage-menu"
  environment                       = var.env
  role_arn                          = module.manage_menu_role.role_arn
  ecr_repository_url                = module.manage_menu_ecr.manage_menu_ecr_repository_url
  menu_table_name                   = module.menu.table_name
  scheduler_invoke_role_arn         = module.scheduler_invoke_reactivate_menu_item_role.role_arn
  reactivate_menu_item_function_arn = module.reactivate_menu_item_fn.alias_arn
  region                            = var.aws_region
  tenant_table_name                 = module.tenant.table_name
  location_table_name               = module.location.table_name
  location_id_index_name            = module.location.location_id_index_name
}
module "manage_order_fn" {
  source                 = "./compute/lambda/manage-order"
  environment            = var.env
  role_arn               = module.manage_order_role.role_arn
  ecr_repository_url     = module.manage_order_ecr.manage_order_ecr_repository_url
  order_table_name       = module.order.table_name
  region                 = var.aws_region
  tenant_table_name      = module.tenant.table_name
  location_table_name    = module.location.table_name
  location_id_index_name = module.location.location_id_index_name
}
module "manage_user_fn" {
  source                 = "./compute/lambda/manage-user"
  environment            = var.env
  role_arn               = module.manage_user_role.role_arn
  ecr_repository_url     = module.manage_user_ecr.manage_user_ecr_repository_url
  user_table_name        = module.user.table_name
  user_tenant_index_name = module.user.tenant_index_name
  cognito_user_pool_id   = module.cognito.user_pool_id
  region                 = var.aws_region
  tenant_table_name      = module.tenant.table_name
  location_table_name    = module.location.table_name
  location_id_index_name = module.location.location_id_index_name
}
module "mark_arrived_fn" {
  source                 = "./compute/lambda/mark-arrived"
  environment            = var.env
  role_arn               = module.mark_arrived_role.role_arn
  ecr_repository_url     = module.mark_arrived_ecr.mark_arrived_ecr_repository_url
  reservation_table_name = module.reservation.table_name
  region                 = var.aws_region
  tenant_table_name      = module.tenant.table_name
  location_table_name    = module.location.table_name
  location_id_index_name = module.location.location_id_index_name
}
module "no_show_check_fn" {
  source                         = "./compute/lambda/no-show-check"
  environment                    = var.env
  role_arn                       = module.no_show_check_role.role_arn
  ecr_repository_url             = module.no_show_check_ecr.no_show_check_ecr_repository_url
  location_table_name            = module.location.table_name
  slot_occupancy_table_name      = module.slot_occupancy.table_name
  reservation_table_name         = module.reservation.table_name
  payment_delinquency_table_name = module.payment_delinquency.table_name
  region                         = var.aws_region
  failure_destination_arn        = module.dead_letter.scheduled_invocation_dlq_arn
  tenant_table_name              = module.tenant.table_name
  location_id_index_name         = module.location.location_id_index_name
}
module "notification_fn" {
  source                 = "./compute/lambda/notification"
  environment            = var.env
  role_arn               = module.notification_role.role_arn
  ecr_repository_url     = module.notification_ecr.notification_ecr_repository_url
  no_reply_email_address = local.no_reply_email
  admin_dashboard_url    = local.admin_app_url
  region                 = var.aws_region

  customer_site_url                    = local.customer_site_url
  catering_link_signing_key_secret_arn = module.catering_secrets.link_signing_key_secret_arn
  tenant_table_name                    = module.tenant.table_name
  location_table_name                  = module.location.table_name
  location_id_index_name               = module.location.location_id_index_name
}
module "pre_signed_url_fn" {
  source                  = "./compute/lambda/pre-signed-url"
  environment             = var.env
  role_arn                = module.pre_signed_url_role.role_arn
  ecr_repository_url      = module.pre_signed_url_ecr.pre_signed_url_ecr_repository_url
  menu_images_bucket_name = module.menu_image.bucket_name
  region                  = var.aws_region
  tenant_table_name       = module.tenant.table_name
  location_table_name     = module.location.table_name
  location_id_index_name  = module.location.location_id_index_name
}
module "publish_layout_fn" {
  source                               = "./compute/lambda/publish-layout"
  environment                          = var.env
  role_arn                             = module.publish_layout_role.role_arn
  ecr_repository_url                   = module.publish_layout_ecr.publish_layout_ecr_repository_url
  live_layout_element_table_name       = module.live_layout_element.table_name
  published_layout_snapshot_table_name = module.published_layout_snapshot.table_name
  region                               = var.aws_region
  tenant_table_name                    = module.tenant.table_name
  location_table_name                  = module.location.table_name
  location_id_index_name               = module.location.location_id_index_name
}
module "stripe_webhook_fn" {
  source                         = "./compute/lambda/stripe-webhook"
  environment                    = var.env
  role_arn                       = module.stripe_webhook_role.role_arn
  ecr_repository_url             = module.stripe_webhook_ecr.stripe_webhook_ecr_repository_url
  location_table_name            = module.location.table_name
  reservation_table_name         = module.reservation.table_name
  payment_delinquency_table_name = module.payment_delinquency.table_name
  scheduler_invoke_role_arn      = module.scheduler_invoke_no_show_check_role.role_arn
  no_show_check_function_arn     = module.no_show_check_fn.alias_arn
  region                         = var.aws_region
  stripe_webhook_secret_arn      = module.stripe_webhooks.reservation_webhook_secret_arn
  tenant_table_name              = module.tenant.table_name
  location_id_index_name         = module.location.location_id_index_name
}
module "webhook_payment_intent_fn" {
  source                          = "./compute/lambda/webhook-payment-intent"
  environment                     = var.env
  role_arn                        = module.webhook_payment_intent_role.role_arn
  ecr_repository_url              = module.webhook_payment_intent_ecr.webhook_payment_intent_ecr_repository_url
  order_table_name                = module.order.table_name
  region                          = var.aws_region
  order_stripe_webhook_secret_arn = module.stripe_webhooks.order_webhook_secret_arn
  tenant_table_name               = module.tenant.table_name
  location_table_name             = module.location.table_name
  location_id_index_name          = module.location.location_id_index_name
}
module "catering_settings_fn" {
  source                 = "./compute/lambda/catering-settings"
  environment            = var.env
  role_arn               = module.catering_settings_role.role_arn
  ecr_repository_url     = module.catering_settings_ecr.catering_settings_ecr_repository_url
  location_table_name    = module.location.table_name
  region                 = var.aws_region
  tenant_table_name      = module.tenant.table_name
  location_id_index_name = module.location.location_id_index_name
}
module "catering_discount_tiers_fn" {
  source                             = "./compute/lambda/catering-discount-tiers"
  environment                        = var.env
  role_arn                           = module.catering_discount_tiers_role.role_arn
  ecr_repository_url                 = module.catering_discount_tiers_ecr.catering_discount_tiers_ecr_repository_url
  catering_discount_tiers_table_name = module.catering_discount_tiers.table_name
  region                             = var.aws_region
  tenant_table_name                  = module.tenant.table_name
  location_table_name                = module.location.table_name
  location_id_index_name             = module.location.location_id_index_name
}
module "catering_requests_fn" {
  source                             = "./compute/lambda/catering-requests"
  environment                        = var.env
  role_arn                           = module.catering_requests_role.role_arn
  ecr_repository_url                 = module.catering_requests_ecr.catering_requests_ecr_repository_url
  catering_requests_table_name       = module.catering_requests.table_name
  location_table_name                = module.location.table_name
  catering_discount_tiers_table_name = module.catering_discount_tiers.table_name
  menu_table_name                    = module.menu.table_name
  region                             = var.aws_region

  catering_request_history_table_name = module.catering_request_history.table_name
  turnstile_secret_arn                = module.catering_secrets.turnstile_secret_arn
  link_signing_key_secret_arn         = module.catering_secrets.link_signing_key_secret_arn
  customer_site_url                   = local.customer_site_url
  tenant_table_name                   = module.tenant.table_name
  location_id_index_name              = module.location.location_id_index_name
}
module "catering_offer_fn" {
  source                              = "./compute/lambda/catering-offer"
  environment                         = var.env
  role_arn                            = module.catering_offer_role.role_arn
  ecr_repository_url                  = module.catering_offer_ecr.catering_offer_ecr_repository_url
  catering_requests_table_name        = module.catering_requests.table_name
  catering_request_history_table_name = module.catering_request_history.table_name
  location_table_name                 = module.location.table_name
  menu_table_name                     = module.menu.table_name
  catering_documents_bucket_name      = module.catering_documents.bucket_name
  document_function_name              = "${module.catering_document_fn.function_name}:${module.catering_document_fn.alias_name}"
  stripe_secret_arn                   = module.platform_secrets.stripe_secret_arn
  stripe_api_version                  = var.stripe_api_version
  region                              = var.aws_region
  tenant_table_name                   = module.tenant.table_name
  location_id_index_name              = module.location.location_id_index_name
}
module "catering_customer_fn" {
  source                              = "./compute/lambda/catering-customer"
  environment                         = var.env
  role_arn                            = module.catering_customer_role.role_arn
  ecr_repository_url                  = module.catering_customer_ecr.catering_customer_ecr_repository_url
  catering_requests_table_name        = module.catering_requests.table_name
  catering_request_history_table_name = module.catering_request_history.table_name
  location_table_name                 = module.location.table_name
  catering_documents_bucket_name      = module.catering_documents.bucket_name
  link_signing_key_secret_arn         = module.catering_secrets.link_signing_key_secret_arn
  signing_provider_secret_arn         = module.catering_secrets.signing_provider_secret_arn
  stripe_secret_arn                   = module.platform_secrets.stripe_secret_arn
  stripe_api_version                  = var.stripe_api_version
  customer_site_url                   = local.customer_site_url
  signing_webhook_url                 = local.catering_signing_webhook_url
  region                              = var.aws_region
  tenant_table_name                   = module.tenant.table_name
  location_id_index_name              = module.location.location_id_index_name
}
module "catering_signing_webhook_fn" {
  source                              = "./compute/lambda/catering-signing-webhook"
  environment                         = var.env
  role_arn                            = module.catering_signing_webhook_role.role_arn
  ecr_repository_url                  = module.catering_signing_webhook_ecr.catering_signing_webhook_ecr_repository_url
  catering_requests_table_name        = module.catering_requests.table_name
  catering_request_history_table_name = module.catering_request_history.table_name
  catering_documents_bucket_name      = module.catering_documents.bucket_name
  signing_provider_secret_arn         = module.catering_secrets.signing_provider_secret_arn
  region                              = var.aws_region
  tenant_table_name                   = module.tenant.table_name
  location_table_name                 = module.location.table_name
  location_id_index_name              = module.location.location_id_index_name
}
module "catering_stripe_webhook_fn" {
  source                              = "./compute/lambda/catering-stripe-webhook"
  environment                         = var.env
  role_arn                            = module.catering_stripe_webhook_role.role_arn
  ecr_repository_url                  = module.catering_stripe_webhook_ecr.catering_stripe_webhook_ecr_repository_url
  catering_requests_table_name        = module.catering_requests.table_name
  catering_request_history_table_name = module.catering_request_history.table_name
  catering_documents_bucket_name      = module.catering_documents.bucket_name
  catering_stripe_webhook_secret_arn  = module.stripe_webhooks.catering_webhook_secret_arn
  stripe_secret_arn                   = module.platform_secrets.stripe_secret_arn
  stripe_api_version                  = var.stripe_api_version
  region                              = var.aws_region
  tenant_table_name                   = module.tenant.table_name
  location_table_name                 = module.location.table_name
  location_id_index_name              = module.location.location_id_index_name
}
module "catering_document_fn" {
  source                              = "./compute/lambda/catering-document"
  environment                         = var.env
  role_arn                            = module.catering_document_role.role_arn
  ecr_repository_url                  = module.catering_document_ecr.catering_document_ecr_repository_url
  catering_request_history_table_name = module.catering_request_history.table_name
  location_table_name                 = module.location.table_name
  catering_documents_bucket_name      = module.catering_documents.bucket_name
  region                              = var.aws_region
  tenant_table_name                   = module.tenant.table_name
  location_id_index_name              = module.location.location_id_index_name
}
module "catering_lifecycle_fn" {
  source                              = "./compute/lambda/catering-lifecycle"
  environment                         = var.env
  role_arn                            = module.catering_lifecycle_role.role_arn
  ecr_repository_url                  = module.catering_lifecycle_ecr.catering_lifecycle_ecr_repository_url
  catering_requests_table_name        = module.catering_requests.table_name
  catering_request_history_table_name = module.catering_request_history.table_name
  location_table_name                 = module.location.table_name
  stripe_secret_arn                   = module.platform_secrets.stripe_secret_arn
  stripe_api_version                  = var.stripe_api_version
  schedule_group_name                 = module.scheduler_invoke_catering_lifecycle_role.schedule_group_name
  scheduler_invoke_role_arn           = module.scheduler_invoke_catering_lifecycle_role.role_arn
  scheduler_dlq_arn                   = module.dead_letter.scheduled_invocation_dlq_arn
  region                              = var.aws_region
  failure_destination_arn             = module.dead_letter.scheduled_invocation_dlq_arn
  tenant_table_name                   = module.tenant.table_name
  location_id_index_name              = module.location.location_id_index_name
}

module "dlq_replay_fn" {
  source                          = "./compute/lambda/dlq-replay"
  environment                     = var.env
  role_arn                        = module.dlq_replay_role.role_arn
  ecr_repository_url              = module.dlq_replay_ecr.dlq_replay_ecr_repository_url
  queue_urls                      = module.dead_letter.queue_urls
  catering_lifecycle_function_arn = module.catering_lifecycle_fn.alias_arn
  notification_function_arn       = module.notification_fn.alias_arn
  replayable_function_arns = [
    module.catering_lifecycle_fn.function_arn,
    module.catering_lifecycle_fn.alias_arn,
    module.no_show_check_fn.function_arn,
    module.no_show_check_fn.alias_arn,
    module.reactivate_menu_item_fn.function_arn,
    module.reactivate_menu_item_fn.alias_arn,
    module.expire_layout_version_fn.function_arn,
    module.expire_layout_version_fn.alias_arn,
  ]
  alert_topic_arn           = module.alerts.topic_arn
  scheduler_invoke_role_arn = module.scheduler_invoke_dlq_replay_role.role_arn
  replay_interval_minutes   = var.dlq_replay_interval_minutes
  region                    = var.aws_region
}

# --- Platform / tenant control plane Lambdas -----------------------------------
module "platform_tenants_fn" {
  source                          = "./compute/lambda/platform-tenants"
  environment                     = var.env
  role_arn                        = module.platform_tenants_role.role_arn
  ecr_repository_url              = module.platform_tenants_ecr.platform_tenants_ecr_repository_url
  tenant_table_name               = module.tenant.table_name
  location_table_name             = module.location.table_name
  location_id_index_name          = module.location.location_id_index_name
  user_table_name                 = module.user.table_name
  user_tenant_index_name          = module.user.tenant_index_name
  tenant_user_pool_id             = module.cognito.user_pool_id
  owner_group_name                = module.cognito.owner_group_name
  onboarding_state_machine_arn    = module.tenant_workflows.onboarding_state_machine_arn
  domain_attach_state_machine_arn = module.tenant_workflows.domain_attach_state_machine_arn
  domain_detach_state_machine_arn = module.tenant_workflows.domain_detach_state_machine_arn
  offboarding_state_machine_arn   = module.tenant_workflows.offboarding_state_machine_arn
  stripe_secret_arn               = module.platform_secrets.stripe_secret_arn
  stripe_api_version              = var.stripe_api_version
  platform_domain                 = var.platform_domain
  tenant_domain_cname_target      = local.tenant_domain_cname_target
  admin_app_url                   = local.admin_app_url
  platform_admin_app_url          = local.platform_admin_app_url
  region                          = var.aws_region
}
module "tenant_account_fn" {
  source                 = "./compute/lambda/tenant-account"
  environment            = var.env
  role_arn               = module.tenant_account_role.role_arn
  ecr_repository_url     = module.tenant_account_ecr.tenant_account_ecr_repository_url
  tenant_table_name      = module.tenant.table_name
  location_table_name    = module.location.table_name
  stripe_secret_arn      = module.platform_secrets.stripe_secret_arn
  stripe_api_version     = var.stripe_api_version
  admin_app_url          = local.admin_app_url
  region                 = var.aws_region
  location_id_index_name = module.location.location_id_index_name
}
module "tenant_site_config_fn" {
  source                 = "./compute/lambda/tenant-site-config"
  environment            = var.env
  role_arn               = module.tenant_site_config_role.role_arn
  ecr_repository_url     = module.tenant_site_config_ecr.tenant_site_config_ecr_repository_url
  tenant_table_name      = module.tenant.table_name
  location_table_name    = module.location.table_name
  turnstile_site_key     = var.turnstile_site_key
  stripe_publishable_key = var.stripe_publishable_key
  region                 = var.aws_region
  location_id_index_name = module.location.location_id_index_name
}
module "platform_stripe_webhook_fn" {
  source                     = "./compute/lambda/platform-stripe-webhook"
  environment                = var.env
  role_arn                   = module.platform_stripe_webhook_role.role_arn
  ecr_repository_url         = module.platform_stripe_webhook_ecr.platform_stripe_webhook_ecr_repository_url
  tenant_table_name          = module.tenant.table_name
  connect_webhook_secret_arn = module.stripe_webhooks.platform_connect_webhook_secret_arn
  billing_webhook_secret_arn = module.stripe_webhooks.platform_billing_webhook_secret_arn
  stripe_secret_arn          = module.platform_secrets.stripe_secret_arn
  stripe_api_version         = var.stripe_api_version
  region                     = var.aws_region
}


#Monitoring
module "alerts" {
  source                  = "./monitoring/alerts"
  environment             = var.env
  region                  = var.aws_region
  alert_emails            = var.alert_emails
  dlq_queue_names         = module.dead_letter.queue_names
  replay_function_name    = module.dlq_replay_fn.function_name
  replay_interval_minutes = var.dlq_replay_interval_minutes
}

# Blue/green releases (CodeDeploy) for every container-image Lambda - see
# orchestration/lambda-releases. pre-token-generation is not listed: its
# code ships from this repo and its alias follows Terraform directly.
module "lambda_releases" {
  source          = "./orchestration/lambda-releases"
  environment     = var.env
  alert_topic_arn = module.alerts.topic_arn

  # prod: 10% of traffic for 5 minutes, then 100%, rolled back automatically
  # if the function's error-rate or throttle alarm fires.
  # dev: all at once, no alarms (they are billed monthly even when idle);
  # a deployment that fails outright is still rolled back.
  # For the linear rollout (10% more every minute) set type
  # "TimeBasedLinear" and interval 1 - once prod traffic is steady enough
  # for 1-minute alarm windows to see real requests.
  traffic_shift_type             = var.env == "prod" ? "TimeBasedCanary" : "AllAtOnce"
  traffic_shift_percentage       = 10
  traffic_shift_interval_minutes = 5
  rollback_alarms_enabled        = var.env == "prod"

  functions = {
    (module.activate_layout_version_fn.function_name)    = { alias_name = module.activate_layout_version_fn.alias_name }
    (module.block_table_fn.function_name)                = { alias_name = module.block_table_fn.alias_name }
    (module.cancel_reservation_fn.function_name)         = { alias_name = module.cancel_reservation_fn.alias_name }
    (module.catering_customer_fn.function_name)          = { alias_name = module.catering_customer_fn.alias_name }
    (module.catering_discount_tiers_fn.function_name)    = { alias_name = module.catering_discount_tiers_fn.alias_name }
    (module.catering_document_fn.function_name)          = { alias_name = module.catering_document_fn.alias_name }
    (module.catering_lifecycle_fn.function_name)         = { alias_name = module.catering_lifecycle_fn.alias_name }
    (module.catering_offer_fn.function_name)             = { alias_name = module.catering_offer_fn.alias_name }
    (module.catering_requests_fn.function_name)          = { alias_name = module.catering_requests_fn.alias_name }
    (module.catering_settings_fn.function_name)          = { alias_name = module.catering_settings_fn.alias_name }
    (module.catering_signing_webhook_fn.function_name)   = { alias_name = module.catering_signing_webhook_fn.alias_name }
    (module.catering_stripe_webhook_fn.function_name)    = { alias_name = module.catering_stripe_webhook_fn.alias_name }
    (module.create_location_fn.function_name)            = { alias_name = module.create_location_fn.alias_name }
    (module.create_pending_reservation_fn.function_name) = { alias_name = module.create_pending_reservation_fn.alias_name }
    (module.dlq_replay_fn.function_name)                 = { alias_name = module.dlq_replay_fn.alias_name }
    (module.expire_layout_version_fn.function_name)      = { alias_name = module.expire_layout_version_fn.alias_name }
    (module.get_availability_fn.function_name)           = { alias_name = module.get_availability_fn.alias_name }
    (module.get_location_fn.function_name)               = { alias_name = module.get_location_fn.alias_name }
    (module.get_menu_fn.function_name)                   = { alias_name = module.get_menu_fn.alias_name }
    (module.get_order_fn.function_name)                  = { alias_name = module.get_order_fn.alias_name }
    (module.get_reservation_fn.function_name)            = { alias_name = module.get_reservation_fn.alias_name }
    (module.list_layout_version_fn.function_name)        = { alias_name = module.list_layout_version_fn.alias_name }
    (module.manage_auth_fn.function_name)                = { alias_name = module.manage_auth_fn.alias_name }
    (module.manage_layout_element_fn.function_name)      = { alias_name = module.manage_layout_element_fn.alias_name }
    (module.manage_menu_fn.function_name)                = { alias_name = module.manage_menu_fn.alias_name }
    (module.manage_order_fn.function_name)               = { alias_name = module.manage_order_fn.alias_name }
    (module.manage_user_fn.function_name)                = { alias_name = module.manage_user_fn.alias_name }
    (module.mark_arrived_fn.function_name)               = { alias_name = module.mark_arrived_fn.alias_name }
    (module.no_show_check_fn.function_name)              = { alias_name = module.no_show_check_fn.alias_name }
    (module.notification_fn.function_name)               = { alias_name = module.notification_fn.alias_name }
    (module.payment_intent_fn.function_name)             = { alias_name = module.payment_intent_fn.alias_name }
    (module.platform_stripe_webhook_fn.function_name)    = { alias_name = module.platform_stripe_webhook_fn.alias_name }
    (module.platform_tenants_fn.function_name)           = { alias_name = module.platform_tenants_fn.alias_name }
    (module.pre_signed_url_fn.function_name)             = { alias_name = module.pre_signed_url_fn.alias_name }
    (module.publish_layout_fn.function_name)             = { alias_name = module.publish_layout_fn.alias_name }
    (module.reactivate_menu_item_fn.function_name)       = { alias_name = module.reactivate_menu_item_fn.alias_name }
    (module.stripe_webhook_fn.function_name)             = { alias_name = module.stripe_webhook_fn.alias_name }
    (module.tenant_account_fn.function_name)             = { alias_name = module.tenant_account_fn.alias_name }
    (module.tenant_site_config_fn.function_name)         = { alias_name = module.tenant_site_config_fn.alias_name }
    (module.webhook_payment_intent_fn.function_name)     = { alias_name = module.webhook_payment_intent_fn.alias_name }
  }
}


#API Gateway
module "api_gateway" {
  source               = "./network/api-gateway"
  environment          = var.env
  region               = var.aws_region
  cognito_user_pool_id = module.cognito.user_pool_id
  cognito_client_id    = module.cognito.user_pool_client_id
  # Tenant websites live on domains added at runtime - see the CORS note in
  # network/api-gateway (bearer tokens only, so "*" is safe here).
  allowed_origins                          = ["*"]
  platform_user_pool_id                    = module.cognito_platform.user_pool_id
  platform_client_id                       = module.cognito_platform.client_id
  platform_admin_scope                     = module.cognito_platform.admin_scope
  platform_tenants_function_name           = module.platform_tenants_fn.function_name
  platform_tenants_invoke_arn              = module.platform_tenants_fn.alias_invoke_arn
  tenant_account_function_name             = module.tenant_account_fn.function_name
  tenant_account_invoke_arn                = module.tenant_account_fn.alias_invoke_arn
  tenant_site_config_function_name         = module.tenant_site_config_fn.function_name
  tenant_site_config_invoke_arn            = module.tenant_site_config_fn.alias_invoke_arn
  get_location_function_name               = module.get_location_fn.function_name
  get_location_invoke_arn                  = module.get_location_fn.alias_invoke_arn
  create_location_function_name            = module.create_location_fn.function_name
  create_location_invoke_arn               = module.create_location_fn.alias_invoke_arn
  get_menu_function_name                   = module.get_menu_fn.function_name
  get_menu_invoke_arn                      = module.get_menu_fn.alias_invoke_arn
  manage_menu_function_name                = module.manage_menu_fn.function_name
  manage_menu_invoke_arn                   = module.manage_menu_fn.alias_invoke_arn
  manage_order_function_name               = module.manage_order_fn.function_name
  manage_order_invoke_arn                  = module.manage_order_fn.alias_invoke_arn
  get_availability_function_name           = module.get_availability_fn.function_name
  get_availability_invoke_arn              = module.get_availability_fn.alias_invoke_arn
  create_pending_reservation_function_name = module.create_pending_reservation_fn.function_name
  create_pending_reservation_invoke_arn    = module.create_pending_reservation_fn.alias_invoke_arn
  get_reservation_function_name            = module.get_reservation_fn.function_name
  get_reservation_invoke_arn               = module.get_reservation_fn.alias_invoke_arn
  get_order_function_name                  = module.get_order_fn.function_name
  get_order_invoke_arn                     = module.get_order_fn.alias_invoke_arn
  payment_intent_function_name             = module.payment_intent_fn.function_name
  payment_intent_invoke_arn                = module.payment_intent_fn.alias_invoke_arn
  cancel_reservation_function_name         = module.cancel_reservation_fn.function_name
  cancel_reservation_invoke_arn            = module.cancel_reservation_fn.alias_invoke_arn
  mark_arrived_function_name               = module.mark_arrived_fn.function_name
  mark_arrived_invoke_arn                  = module.mark_arrived_fn.alias_invoke_arn
  block_table_function_name                = module.block_table_fn.function_name
  block_table_invoke_arn                   = module.block_table_fn.alias_invoke_arn
  manage_layout_element_function_name      = module.manage_layout_element_fn.function_name
  manage_layout_element_invoke_arn         = module.manage_layout_element_fn.alias_invoke_arn
  publish_layout_function_name             = module.publish_layout_fn.function_name
  publish_layout_invoke_arn                = module.publish_layout_fn.alias_invoke_arn
  list_layout_version_function_name        = module.list_layout_version_fn.function_name
  list_layout_version_invoke_arn           = module.list_layout_version_fn.alias_invoke_arn
  activate_layout_version_function_name    = module.activate_layout_version_fn.function_name
  activate_layout_version_invoke_arn       = module.activate_layout_version_fn.alias_invoke_arn
  manage_auth_function_name                = module.manage_auth_fn.function_name
  manage_auth_invoke_arn                   = module.manage_auth_fn.alias_invoke_arn
  manage_user_function_name                = module.manage_user_fn.function_name
  manage_user_invoke_arn                   = module.manage_user_fn.alias_invoke_arn
  pre_signed_url_function_name             = module.pre_signed_url_fn.function_name
  pre_signed_url_invoke_arn                = module.pre_signed_url_fn.alias_invoke_arn
  catering_settings_function_name          = module.catering_settings_fn.function_name
  catering_settings_invoke_arn             = module.catering_settings_fn.alias_invoke_arn
  catering_discount_tiers_function_name    = module.catering_discount_tiers_fn.function_name
  catering_discount_tiers_invoke_arn       = module.catering_discount_tiers_fn.alias_invoke_arn
  catering_requests_function_name          = module.catering_requests_fn.function_name
  catering_requests_invoke_arn             = module.catering_requests_fn.alias_invoke_arn
  catering_offer_function_name             = module.catering_offer_fn.function_name
  catering_offer_invoke_arn                = module.catering_offer_fn.alias_invoke_arn
  catering_customer_function_name          = module.catering_customer_fn.function_name
  catering_customer_invoke_arn             = module.catering_customer_fn.alias_invoke_arn
  catering_signing_webhook_function_name   = module.catering_signing_webhook_fn.function_name
  catering_signing_webhook_invoke_arn      = module.catering_signing_webhook_fn.alias_invoke_arn
}

# Stripe webhook endpoints - created in Stripe by Terraform, pointing straight
# at each webhook Lambda's Function URL (no API Gateway). Each endpoint's
# signing secret is written to Secrets Manager; the Lambda gets the secret's
# ARN (see payments/stripe for why it can't be the value itself).
module "stripe_webhooks" {
  source                  = "./payments/stripe"
  environment             = var.env
  reservation_webhook_url = module.stripe_webhook_fn.function_url
  order_webhook_url       = module.webhook_payment_intent_fn.function_url
  catering_webhook_url    = module.catering_stripe_webhook_fn.function_url
  platform_webhook_url    = module.platform_stripe_webhook_fn.function_url
}

# Values several modules share - computed once so links, sender addresses
# and app URLs all agree.
locals {
  # Fallback base URL for customer links while a tenant has no domain yet
  # (dev / before platform_domain is set). Handlers prefer the tenant's
  # primaryDomain - see docs/handoff/BACKEND.md.
  customer_site_url            = "https://${module.cloudfront_public.distribution_domain_name}"
  catering_signing_webhook_url = "${module.api_gateway.api_endpoint}/webhooks/signing/catering"

  # Everything that needs a domain the platform owns switches on with
  # var.platform_domain (network/platform-domain).
  platform_domain_enabled = var.platform_domain != ""

  admin_app_url          = local.platform_domain_enabled ? "https://app.${var.platform_domain}" : "https://${module.cloudfront_private.distribution_domain_name}"
  platform_admin_app_url = local.platform_domain_enabled ? "https://ops.${var.platform_domain}" : "https://${module.cloudfront_platform_admin.distribution_domain_name}"
  # Every origin the operator app may sign in from (OAuth callback URLs).
  platform_admin_app_urls = distinct(concat(
    ["https://${module.cloudfront_platform_admin.distribution_domain_name}"],
    local.platform_domain_enabled ? ["https://ops.${var.platform_domain}"] : [],
    var.env == "prod" ? [] : ["http://localhost:5173"],
  ))

  # One sender for all tenants (their name goes in the display name, their
  # address in Reply-To): mail.<platform domain> once it exists.
  no_reply_email        = local.platform_domain_enabled ? module.platform_domain[0].no_reply_address : var.no_reply_email_address
  no_reply_from_address = local.no_reply_email
  ses_identity_arn      = local.platform_domain_enabled ? module.platform_domain[0].ses_identity_arn : module.ses.identity_arn

  tenant_domain_cname_target = local.platform_domain_enabled ? module.platform_domain[0].cname_target : ""

  # Every application Lambda that serves tenant data gets the shared
  # tenant-context read policy (security/iam/tenant-context). Not here:
  # pre-token-generation (no data access), manage-auth (login proxy),
  # dlq-replay (re-delivers events to the owners below), scheduler and
  # GitHub deploy roles.
  tenant_aware_role_names = {
    activate_layout_version    = module.activate_layout_version_role.role_name
    block_table                = module.block_table_role.role_name
    cancel_reservation         = module.cancel_reservation_role.role_name
    catering_customer          = module.catering_customer_role.role_name
    catering_discount_tiers    = module.catering_discount_tiers_role.role_name
    catering_document          = module.catering_document_role.role_name
    catering_lifecycle         = module.catering_lifecycle_role.role_name
    catering_offer             = module.catering_offer_role.role_name
    catering_requests          = module.catering_requests_role.role_name
    catering_settings          = module.catering_settings_role.role_name
    catering_signing_webhook   = module.catering_signing_webhook_role.role_name
    catering_stripe_webhook    = module.catering_stripe_webhook_role.role_name
    create_location            = module.create_location_role.role_name
    create_pending_reservation = module.create_pending_reservation_role.role_name
    expire_layout_version      = module.expire_layout_version_role.role_name
    get_availability           = module.get_availability_role.role_name
    get_location               = module.get_location_role.role_name
    get_menu                   = module.get_menu_role.role_name
    get_order                  = module.get_order_role.role_name
    get_reservation            = module.get_reservation_role.role_name
    list_layout_version        = module.list_layout_version_role.role_name
    manage_layout_element      = module.manage_layout_element_role.role_name
    manage_menu                = module.manage_menu_role.role_name
    manage_order               = module.manage_order_role.role_name
    manage_user                = module.manage_user_role.role_name
    mark_arrived               = module.mark_arrived_role.role_name
    no_show_check              = module.no_show_check_role.role_name
    notification               = module.notification_role.role_name
    payment_intent             = module.payment_intent_role.role_name
    platform_stripe_webhook    = module.platform_stripe_webhook_role.role_name
    platform_tenants           = module.platform_tenants_role.role_name
    pre_signed_url             = module.pre_signed_url_role.role_name
    publish_layout             = module.publish_layout_role.role_name
    reactivate_menu_item       = module.reactivate_menu_item_role.role_name
    stripe_webhook             = module.stripe_webhook_role.role_name
    tenant_account             = module.tenant_account_role.role_name
    tenant_site_config         = module.tenant_site_config_role.role_name
    webhook_payment_intent     = module.webhook_payment_intent_role.role_name
  }
}

# --- Platform domain (off until var.platform_domain is set) --------------------
module "platform_domain" {
  count  = local.platform_domain_enabled ? 1 : 0
  source = "./network/platform-domain"
  providers = {
    aws           = aws
    aws.us_east_1 = aws.us_east_1
  }

  environment                             = var.env
  platform_domain                         = var.platform_domain
  menu_image_bucket_regional_domain_name  = module.menu_image.bucket_regional_domain_name
  admin_distribution_domain_name          = module.cloudfront_private.distribution_domain_name
  platform_admin_distribution_domain_name = module.cloudfront_platform_admin.distribution_domain_name
}

# --- Control plane workflows --------------------------------------------------------
module "tenant_workflows" {
  source = "./orchestration/tenant-workflows"

  environment             = var.env
  region                  = var.aws_region
  tenant_table_name       = module.tenant.table_name
  tenant_table_arn        = module.tenant.table_arn
  user_table_name         = module.user.table_name
  user_table_arn          = module.user.table_arn
  user_tenant_index_name  = module.user.tenant_index_name
  tenant_user_pool_id     = module.cognito.user_pool_id
  tenant_user_pool_arn    = module.cognito.user_pool_arn
  owner_group_name        = module.cognito.owner_group_name
  stripe_secret_key       = var.stripe_secret_key
  stripe_api_version      = var.stripe_api_version
  default_tax_rates       = var.default_tax_rates
  alert_topic_arn         = module.alerts.topic_arn
  platform_domain_enabled = local.platform_domain_enabled
  platform_domain         = var.platform_domain

  multitenant_distribution_id  = local.platform_domain_enabled ? module.platform_domain[0].multitenant_distribution_id : ""
  multitenant_distribution_arn = local.platform_domain_enabled ? module.platform_domain[0].multitenant_distribution_arn : ""
  connection_group_id          = local.platform_domain_enabled ? module.platform_domain[0].connection_group_id : ""
  connection_group_arn         = local.platform_domain_enabled ? module.platform_domain[0].connection_group_arn : ""
  cname_target                 = local.tenant_domain_cname_target
  sites_bucket_name            = local.platform_domain_enabled ? module.platform_domain[0].sites_bucket_name : ""
  sites_bucket_arn             = local.platform_domain_enabled ? module.platform_domain[0].sites_bucket_arn : ""
}

#CloudFront
module "cloudfront_public" {
  source                                 = "./network/cloudfront/public"
  environment                            = var.env
  customer_bucket_regional_domain_name   = module.customer_front_end_asset.bucket_regional_domain_name
  menu_image_bucket_regional_domain_name = module.menu_image.bucket_regional_domain_name
}
module "cloudfront_private" {
  source                                 = "./network/cloudfront/private"
  environment                            = var.env
  admin_bucket_regional_domain_name      = module.admin_front_end_asset.bucket_regional_domain_name
  menu_image_bucket_regional_domain_name = module.menu_image.bucket_regional_domain_name
  aliases                                = local.platform_domain_enabled ? ["app.${var.platform_domain}"] : []
  acm_certificate_arn                    = local.platform_domain_enabled ? module.platform_domain[0].certificate_arn : ""
}
# Operator app (platform admin) - where tenants are created and managed
module "cloudfront_platform_admin" {
  source                      = "./network/cloudfront/platform-admin"
  environment                 = var.env
  bucket_regional_domain_name = module.platform_admin_front_end_asset.bucket_regional_domain_name
  aliases                     = local.platform_domain_enabled ? ["ops.${var.platform_domain}"] : []
  acm_certificate_arn         = local.platform_domain_enabled ? module.platform_domain[0].certificate_arn : ""
}

#OIDC
module "github_oidc_provider" {
  source      = "./security/iam/oidc/provider"
  environment = var.env
}
module "customer_front_end_role" {
  source                      = "./security/iam/oidc/customer-front-end-role"
  environment                 = var.env
  oidc_provider_arn           = module.github_oidc_provider.provider_arn
  github_repo                 = "${var.github_org}@*/${var.customer_frontend_repo}"
  customer_bucket_arn         = module.customer_front_end_asset.bucket_arn
  cloudfront_distribution_arn = module.cloudfront_public.distribution_arn
}
module "admin_front_end_role" {
  source                      = "./security/iam/oidc/admin-front-end-role"
  environment                 = var.env
  oidc_provider_arn           = module.github_oidc_provider.provider_arn
  github_repo                 = "${var.github_org}@*/${var.admin_frontend_repo}"
  admin_bucket_arn            = module.admin_front_end_asset.bucket_arn
  cloudfront_distribution_arn = module.cloudfront_private.distribution_arn
}
module "platform_admin_front_end_role" {
  source                          = "./security/iam/oidc/platform-admin-front-end-role"
  environment                     = var.env
  oidc_provider_arn               = module.github_oidc_provider.provider_arn
  github_repo                     = "${var.github_org}@*/${var.platform_admin_frontend_repo}"
  platform_admin_bucket_arn       = module.platform_admin_front_end_asset.bucket_arn
  cloudfront_distribution_arn     = module.cloudfront_platform_admin.distribution_arn
  api_ecr_repository_arn          = module.platform_tenants_ecr.platform_tenants_ecr_repository_arn
  api_function_arn                = module.platform_tenants_fn.function_arn
  codedeploy_app_arn              = module.lambda_releases.app_arn
  codedeploy_deployment_group_arn = module.lambda_releases.deployment_group_arns[module.platform_tenants_fn.function_name]
  alert_topic_arn                 = module.alerts.topic_arn
}
# Tenant website repos (site-*) publish to the tenant-sites bucket
module "tenant_sites_deploy_role" {
  count             = local.platform_domain_enabled ? 1 : 0
  source            = "./security/iam/oidc/tenant-sites-deploy-role"
  environment       = var.env
  oidc_provider_arn = module.github_oidc_provider.provider_arn
  github_org        = var.github_org
  site_repo_pattern = var.tenant_site_repo_pattern
  sites_bucket_arn  = module.platform_domain[0].sites_bucket_arn
}
module "back_end_role" {
  source              = "./security/iam/oidc/back-end-role"
  environment         = var.env
  oidc_provider_arn   = module.github_oidc_provider.provider_arn
  github_repo         = "${var.github_org}@*/${var.backend_repo}"
  region              = var.aws_region
  codedeploy_app_name = module.lambda_releases.app_name
  alert_topic_arn     = module.alerts.topic_arn
}
