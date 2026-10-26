
terraform {
  required_version = ">= 1.14.0, < 2.0.0"
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
    # The shared secret between the admin app's CloudFront and the API
    # (random_password.cloudfront_edge)
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

# Primary provider - all resources deploy to Stockholm (eu-north-1) for GDPR data residency
provider "aws" {
  region = var.aws_region
}

# ACM certificates for CloudFront MUST be in us-east-1 - AWS hard requirement
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
# Attempt limits for online bookings (per IP address / phone / e-mail).
module "request_guard" {
  source      = "./storage/dynamodb/request-guard"
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
module "catering_menu" {
  source      = "./storage/dynamodb/catering-menu"
  environment = var.env
}
module "catering_request_history" {
  source      = "./storage/dynamodb/catering-request-history"
  environment = var.env
}
# Control plane: tenants, their domains/plan/Stripe account, plan catalog
module "tenant" {
  source           = "./storage/dynamodb/tenant"
  environment      = var.env
  plans            = var.plans
  plan_price_ids   = module.billing_catalog.price_ids
  plan_product_ids = module.billing_catalog.product_ids
}
# Per-customer per-day figures (usage, allocated AWS cost, revenue) and the
# invoice ledger behind Booqy Console's Finance page. Not purged.
module "finance" {
  source      = "./storage/dynamodb/finance"
  environment = var.env
}
# A restaurant's own figures per location and day (Statistik in the admin
# app). Purged with the restaurant (tenant_purge_tables).
module "insights" {
  source      = "./storage/dynamodb/insights"
  environment = var.env
}
# The subscription catalog in the platform Stripe account: a product and a
# monthly price per plan (var.plans.price_sek) and the Swedish VAT rate.
module "billing_catalog" {
  source      = "./payments/billing"
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
# Reservation manage-link signing key + read access for the functions that
# build (create, notification) or verify (guest get / cancel) the link.
module "reservation_secrets" {
  source      = "./security/secrets/reservations"
  environment = var.env
  reader_role_names = {
    create_pending_reservation = module.create_pending_reservation_role.role_name
    cancel_reservation         = module.cancel_reservation_role.role_name
    get_reservation            = module.get_reservation_role.role_name
    notification               = module.notification_role.role_name
    # Food orders: status tokens and table QR codes.
    payment_intent = module.payment_intent_role.role_name
    get_order      = module.get_order_role.role_name
    manage_order   = module.manage_order_role.role_name
  }
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
  additional_cloudfront_distribution_arns = local.tenant_sites_enabled ? [module.platform_domain[0].multitenant_distribution_arn] : []
  allowed_origins = distinct([
    "https://${module.cloudfront_public.distribution_domain_name}",
    "https://${module.cloudfront_private.distribution_domain_name}",
    local.admin_app_url, # restaurang.<platform domain> once set - presigned uploads come from there
  ])
}
module "customer_front_end_asset" {
  source                                  = "./storage/s3/customer-front-end-asset"
  environment                             = var.env
  cloudfront_distribution_arn             = module.cloudfront_public.distribution_arn
  additional_cloudfront_distribution_arns = local.tenant_sites_enabled ? [module.platform_domain[0].multitenant_distribution_arn] : []
}
module "domain_documents" {
  source          = "./storage/s3/domain-documents"
  environment     = var.env
  allowed_origins = local.platform_admin_app_urls
}
module "catering_documents" {
  source      = "./storage/s3/catering-documents"
  environment = var.env
}

# Dev mail outbox (var.mail_outbox): emails saved to S3 instead of SES.
module "mail_outbox" {
  count       = local.mail_outbox_enabled ? 1 : 0
  source      = "./storage/s3/mail-outbox"
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
  custom_message_lambda_arn          = module.tenant_custom_message_fn.alias_arn
  custom_message_function_name       = module.tenant_custom_message_fn.function_name
  admin_app_url                      = local.admin_app_url
  invites_via_ses                    = var.cognito_invites_via_ses
  ses_identity_arn                   = local.ses_identity_arn
  invite_from_address                = local.no_reply_from_address
  refresh_token_rotation_enabled     = var.refresh_token_rotation_enabled
}
# Operator pool - you; the only tokens /platform/* accepts
module "cognito_platform" {
  source                       = "./storage/cognito-platform"
  environment                  = var.env
  operator_emails              = var.platform_operator_emails
  app_urls                     = local.platform_admin_app_urls
  console_url                  = local.platform_admin_app_url
  invites_via_ses              = var.cognito_invites_via_ses
  ses_identity_arn             = local.ses_identity_arn
  from_address                 = local.no_reply_from_address
  custom_message_lambda_arn    = module.operator_custom_message_fn.alias_arn
  custom_message_function_name = module.operator_custom_message_fn.function_name
}


#Network
# Fallback sender while there is no platform domain; with one, mail goes out
# from mail.<platform domain> (network/platform-domain) and this identity is
# simply unused. No count here on purpose: a count would need a `moved` block,
# and Terraform refuses the CI's targeted ECR bootstrap apply while a move is
# pending.
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
# "Forgot password" email triggers (one per user pool) - logs only.
module "tenant_custom_message_role" {
  source      = "./security/iam/cognito-custom-message"
  environment = var.env
  name        = "tenant-custom-message"
  region      = var.aws_region
}
module "operator_custom_message_role" {
  source      = "./security/iam/cognito-custom-message"
  environment = var.env
  name        = "operator-custom-message"
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
  source             = "./security/iam/manage-order"
  environment        = var.env
  order_table_arn    = module.order.table_arn
  location_table_arn = module.location.table_arn
  stripe_secret_arn  = module.platform_secrets.stripe_secret_arn
  region             = var.aws_region
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
  source            = "./security/iam/get-order"
  environment       = var.env
  order_table_arn   = module.order.table_arn
  stripe_secret_arn = module.platform_secrets.stripe_secret_arn
  region            = var.aws_region
}
module "payment_intent_role" {
  source                  = "./security/iam/payment-intent"
  environment             = var.env
  order_table_arn         = module.order.table_arn
  menu_table_arn          = module.menu.table_arn
  region                  = var.aws_region
  stripe_secret_arn       = module.platform_secrets.stripe_secret_arn
  turnstile_secret_arn    = module.catering_secrets.turnstile_secret_arn
  request_guard_table_arn = module.request_guard.table_arn
}
module "mark_arrived_role" {
  source                              = "./security/iam/mark-arrived"
  environment                         = var.env
  reservation_table_arn               = module.reservation.table_arn
  slot_occupancy_table_arn            = module.slot_occupancy.table_arn
  published_layout_snapshot_table_arn = module.published_layout_snapshot.table_arn
  stripe_secret_arn                   = module.platform_secrets.stripe_secret_arn
  region                              = var.aws_region
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
  turnstile_secret_arn                = module.catering_secrets.turnstile_secret_arn
  request_guard_table_arn             = module.request_guard.table_arn
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
  source                  = "./security/iam/manage-auth"
  environment             = var.env
  user_pool_arn           = module.cognito.user_pool_arn
  region                  = var.aws_region
  request_guard_table_arn = module.request_guard.table_arn
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
  from_address                 = local.no_reply_email
  region                       = var.aws_region

  notification_dlq_arn                 = module.dead_letter.notification_stream_dlq_arn
  catering_link_signing_key_secret_arn = module.catering_secrets.link_signing_key_secret_arn
  mail_outbox_enabled                  = local.mail_outbox_enabled
  mail_outbox_bucket_arn               = local.mail_outbox_arn
  finance_table_arn                    = module.finance.table_arn
}
module "catering_settings_role" {
  source                  = "./security/iam/catering-settings"
  environment             = var.env
  location_table_arn      = module.location.table_arn
  catering_menu_table_arn = module.catering_menu.table_arn
  region                  = var.aws_region
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
  catering_menu_table_arn            = module.catering_menu.table_arn
  turnstile_secret_arn               = module.catering_secrets.turnstile_secret_arn
  link_signing_key_secret_arn        = module.catering_secrets.link_signing_key_secret_arn
  request_guard_table_arn            = module.request_guard.table_arn
  region                             = var.aws_region
}
module "catering_offer_role" {
  source                             = "./security/iam/catering-offer"
  environment                        = var.env
  catering_requests_table_arn        = module.catering_requests.table_arn
  catering_request_history_table_arn = module.catering_request_history.table_arn
  location_table_arn                 = module.location.table_arn
  menu_table_arn                     = module.menu.table_arn
  catering_menu_table_arn            = module.catering_menu.table_arn
  catering_documents_bucket_arn      = module.catering_documents.bucket_arn
  stripe_secret_arn                  = module.platform_secrets.stripe_secret_arn
  document_function_arn              = module.catering_document_fn.function_arn
  signing_provider_secret_arn        = module.catering_secrets.signing_provider_secret_arn
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
  request_guard_table_arn            = module.request_guard.table_arn
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
  print_stream_dlq_arn               = module.dead_letter.print_stream_dlq_arn
  print_jobs_function_arn            = module.printing.function_arns["print-jobs"]
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
module "tenant_purge_role" {
  source                 = "./security/iam/tenant-purge"
  environment            = var.env
  region                 = var.aws_region
  tenant_table_arn       = module.tenant.table_arn
  data_table_arns        = values(local.tenant_purge_tables)[*].arn
  user_table_arn         = module.user.table_arn
  user_tenant_index_name = module.user.tenant_index_name
  tenant_user_pool_arn   = module.cognito.user_pool_arn
  menu_image_bucket_arn  = module.menu_image.bucket_arn
  alert_topic_arn        = module.alerts.topic_arn
  protected_zone_ids     = local.platform_domain_enabled ? [module.platform_domain[0].zone_id] : []
}
module "scheduler_invoke_tenant_purge_role" {
  source                  = "./security/iam/scheduler-invoke-tenant-purge"
  environment             = var.env
  tenant_purge_lambda_arn = module.tenant_purge_fn.function_arn
}
module "finance_rollup_role" {
  source                = "./security/iam/finance-rollup"
  environment           = var.env
  region                = var.aws_region
  finance_table_arn     = module.finance.table_arn
  tenant_table_arn      = module.tenant.table_arn
  location_table_arn    = module.location.table_arn
  reservation_table_arn = module.reservation.table_arn
  order_table_arn       = module.order.table_arn
  log_group_names       = local.tenant_aware_log_groups
  alert_topic_arn       = module.alerts.topic_arn
}
module "scheduler_invoke_finance_rollup_role" {
  source                    = "./security/iam/scheduler-invoke-finance-rollup"
  environment               = var.env
  finance_rollup_lambda_arn = module.finance_rollup_fn.function_arn
}
module "insights_rollup_role" {
  source                              = "./security/iam/insights-rollup"
  environment                         = var.env
  region                              = var.aws_region
  insights_table_arn                  = module.insights.table_arn
  tenant_table_arn                    = module.tenant.table_arn
  location_table_arn                  = module.location.table_arn
  reservation_table_arn               = module.reservation.table_arn
  order_table_arn                     = module.order.table_arn
  catering_requests_table_arn         = module.catering_requests.table_arn
  published_layout_snapshot_table_arn = module.published_layout_snapshot.table_arn
  marketing_table_arn                 = module.marketing.table_arn
}
module "scheduler_invoke_insights_rollup_role" {
  source                     = "./security/iam/scheduler-invoke-insights-rollup"
  environment                = var.env
  insights_rollup_lambda_arn = module.insights_rollup_fn.function_arn
}
module "insights_role" {
  source                              = "./security/iam/insights"
  environment                         = var.env
  region                              = var.aws_region
  insights_table_arn                  = module.insights.table_arn
  location_table_arn                  = module.location.table_arn
  reservation_table_arn               = module.reservation.table_arn
  order_table_arn                     = module.order.table_arn
  catering_requests_table_arn         = module.catering_requests.table_arn
  published_layout_snapshot_table_arn = module.published_layout_snapshot.table_arn
  marketing_table_arn                 = module.marketing.table_arn
}
module "scheduler_invoke_platform_tenants_role" {
  source                      = "./security/iam/scheduler-invoke-platform-tenants"
  environment                 = var.env
  platform_tenants_lambda_arn = module.platform_tenants_fn.function_arn
}
module "platform_tenants_role" {
  source                             = "./security/iam/platform-tenants"
  environment                        = var.env
  tenant_table_arn                   = module.tenant.table_arn
  location_table_arn                 = module.location.table_arn
  user_table_arn                     = module.user.table_arn
  tenant_user_pool_arn               = module.cognito.user_pool_arn
  onboarding_state_machine_arn       = module.tenant_workflows.onboarding_state_machine_arn
  domain_attach_state_machine_arn    = module.tenant_workflows.domain_attach_state_machine_arn
  domain_detach_state_machine_arn    = module.tenant_workflows.domain_detach_state_machine_arn
  offboarding_state_machine_arn      = module.tenant_workflows.offboarding_state_machine_arn
  stripe_secret_arn                  = module.platform_secrets.stripe_secret_arn
  region                             = var.aws_region
  operator_user_pool_arn             = module.cognito_platform.user_pool_arn
  domains_enabled                    = local.tenant_sites_enabled
  domain_provision_state_machine_arn = module.tenant_workflows.domain_provision_state_machine_arn
  domain_documents_bucket_arn        = module.domain_documents.bucket_arn
  platform_zone_id                   = local.platform_domain_enabled ? module.platform_domain[0].zone_id : ""
  mail_outbox_enabled                = local.mail_outbox_enabled
  mail_outbox_bucket_arn             = local.mail_outbox_arn
  ses_identity_arn                   = local.ses_identity_arn
  from_address                       = local.no_reply_email
  finance_table_arn                  = module.finance.table_arn
  finance_rollup_lambda_arn          = module.finance_rollup_fn.function_arn
  alert_topic_arn                    = module.alerts.topic_arn
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
module "reservation_reminders_role" {
  source                   = "./security/iam/reservation-reminders"
  environment              = var.env
  location_table_arn       = module.location.table_arn
  reservation_table_arn    = module.reservation.table_arn
  slot_occupancy_table_arn = module.slot_occupancy.table_arn
  region                   = var.aws_region
}
module "scheduler_invoke_reservation_reminders_role" {
  source                           = "./security/iam/scheduler-invoke-reservation-reminders"
  environment                      = var.env
  reservation_reminders_lambda_arn = module.reservation_reminders_fn.function_arn
}
module "platform_stripe_webhook_role" {
  source                     = "./security/iam/platform-stripe-webhook"
  environment                = var.env
  tenant_table_arn           = module.tenant.table_arn
  connect_webhook_secret_arn = module.stripe_webhooks.platform_connect_webhook_secret_arn
  billing_webhook_secret_arn = module.stripe_webhooks.platform_billing_webhook_secret_arn
  stripe_secret_arn          = module.platform_secrets.stripe_secret_arn
  region                     = var.aws_region
  finance_table_arn          = module.finance.table_arn
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

  # Functions where staff_user may act: they read the caller's own user
  # profile to keep staff on their assigned location.
  user_table_arn = module.user.table_arn
  staff_check_role_names = {
    get_location          = module.get_location_role.role_name
    get_menu              = module.get_menu_role.role_name
    manage_menu           = module.manage_menu_role.role_name
    manage_layout_element = module.manage_layout_element_role.role_name
    list_layout_version   = module.list_layout_version_role.role_name
    # GET /tenant lists a staff user's assigned location.
    tenant_account = module.tenant_account_role.role_name
    # Reservations: staff work only on their own location's bookings.
    create_pending_reservation = module.create_pending_reservation_role.role_name
    get_reservation            = module.get_reservation_role.role_name
    mark_arrived               = module.mark_arrived_role.role_name
    # Food orders: staff work only on their own location's orders.
    manage_order = module.manage_order_role.role_name
    # Catering: staff see their own location's requests.
    catering_requests = module.catering_requests_role.role_name
    catering_offer    = module.catering_offer_role.role_name
    # Marketing test emails go to the signed-in owner's own address.
    marketing = module.marketing.role_names["marketing"]
    # Statistik: staff see their own location only.
    insights = module.insights_role.role_name
    # Kitchen printing: staff reprint and test on their own location.
    print_jobs = module.printing.role_names["print-jobs"]
    # Card payments at the till: staff charge on their own location's readers.
    terminal_payments = module.terminal.role_name
    # Kassa: staff sell on their own location's registers.
    kassa = module.kassa.role_name
  }
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
# Marketing: one generic module, one instance per function.
module "marketing_ecr" {
  source      = "./storage/ecr/marketing-function"
  environment = var.env
  function    = "marketing"
}
module "marketing_public_ecr" {
  source      = "./storage/ecr/marketing-function"
  environment = var.env
  function    = "marketing-public"
}
module "marketing_send_ecr" {
  source      = "./storage/ecr/marketing-function"
  environment = var.env
  function    = "marketing-send"
}
module "marketing_sync_ecr" {
  source      = "./storage/ecr/marketing-function"
  environment = var.env
  function    = "marketing-sync"
}
# Kitchen printing (printing.tf)
module "print_jobs_ecr" {
  source      = "./storage/ecr/print-function"
  environment = var.env
  function    = "print-jobs"
}
module "print_device_ecr" {
  source      = "./storage/ecr/print-function"
  environment = var.env
  function    = "print-device"
}
# Card payments at the till (terminal.tf)
module "terminal_payments_ecr" {
  source      = "./storage/ecr/terminal-payments"
  environment = var.env
  function    = "terminal-payments"
}
# Kassa, the till (kassa.tf); same repository settings
module "kassa_ecr" {
  source      = "./storage/ecr/terminal-payments"
  environment = var.env
  function    = "kassa"
}
# Accounting export (accounting.tf); same repository settings
module "accounting_ecr" {
  source      = "./storage/ecr/terminal-payments"
  environment = var.env
  function    = "accounting"
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
module "tenant_purge_ecr" {
  source      = "./storage/ecr/tenant-purge"
  environment = var.env
}
# Guest privacy (privacy-consent.tf); here because CI reads *_ecr from config.tf.
module "data_retention_ecr" {
  source      = "./storage/ecr/data-retention"
  environment = var.env
}
module "guest_privacy_ecr" {
  source      = "./storage/ecr/guest-privacy"
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
module "reservation_reminders_ecr" {
  source      = "./storage/ecr/reservation-reminders"
  environment = var.env
}
module "platform_stripe_webhook_ecr" {
  source      = "./storage/ecr/platform-stripe-webhook"
  environment = var.env
}
module "finance_rollup_ecr" {
  source      = "./storage/ecr/finance-rollup"
  environment = var.env
}
module "insights_ecr" {
  source      = "./storage/ecr/insights"
  environment = var.env
}
module "insights_rollup_ecr" {
  source      = "./storage/ecr/insights-rollup"
  environment = var.env
}


#Compute
# Infra-owned zip Lambda (not an image): Cognito trigger, must never be a placeholder
module "pre_token_generation_fn" {
  source      = "./compute/lambda/pre-token-generation"
  environment = var.env
  role_arn    = module.pre_token_generation_role.role_arn
}
# Infra-owned zip Lambdas: the "forgot password" email as a link to each
# app's reset page (attached to the pools only when they send through SES -
# var.cognito_invites_via_ses).
module "tenant_custom_message_fn" {
  source      = "./compute/lambda/cognito-custom-message"
  environment = var.env
  name        = "tenant-custom-message"
  role_arn    = module.tenant_custom_message_role.role_arn
  reset_url   = "${local.admin_app_url}/aterstall-losenord"
  language    = "sv"
}
module "operator_custom_message_fn" {
  source      = "./compute/lambda/cognito-custom-message"
  environment = var.env
  name        = "operator-custom-message"
  role_arn    = module.operator_custom_message_role.role_arn
  reset_url   = "${local.platform_admin_app_url}/reset-password"
  language    = "en"
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
  source                          = "./compute/lambda/cancel-reservation"
  environment                     = var.env
  role_arn                        = module.cancel_reservation_role.role_arn
  ecr_repository_url              = module.cancel_reservation_ecr.cancel_reservation_ecr_repository_url
  location_table_name             = module.location.table_name
  slot_occupancy_table_name       = module.slot_occupancy.table_name
  reservation_table_name          = module.reservation.table_name
  stripe_secret_arn               = module.platform_secrets.stripe_secret_arn
  region                          = var.aws_region
  tenant_table_name               = module.tenant.table_name
  location_id_index_name          = module.location.location_id_index_name
  reservation_link_key_secret_arn = module.reservation_secrets.link_signing_key_secret_arn
  stripe_api_version              = var.stripe_api_version
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
  privacy_env                          = local.privacy_env_booking
  role_arn                             = module.create_pending_reservation_role.role_arn
  ecr_repository_url                   = module.create_pending_reservation_ecr.create_pending_reservation_ecr_repository_url
  location_table_name                  = module.location.table_name
  published_layout_snapshot_table_name = module.published_layout_snapshot.table_name
  slot_occupancy_table_name            = module.slot_occupancy.table_name
  reservation_table_name               = module.reservation.table_name
  user_table_name                      = module.user.table_name
  payment_delinquency_table_name       = module.payment_delinquency.table_name
  stripe_secret_arn                    = module.platform_secrets.stripe_secret_arn
  region                               = var.aws_region
  tenant_table_name                    = module.tenant.table_name
  location_id_index_name               = module.location.location_id_index_name
  reservation_link_key_secret_arn      = module.reservation_secrets.link_signing_key_secret_arn
  stripe_api_version                   = var.stripe_api_version
  # Bot check on online bookings only once the sites show the widget.
  turnstile_required       = var.turnstile_site_key != ""
  turnstile_secret_arn     = module.catering_secrets.turnstile_secret_arn
  request_guard_table_name = module.request_guard.table_name
  cloudfront_edge_secret   = random_password.cloudfront_edge.result
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
  user_table_name        = module.user.table_name
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
  user_table_name        = module.user.table_name
  location_table_name    = module.location.table_name
  location_id_index_name = module.location.location_id_index_name
}
module "get_reservation_fn" {
  source                          = "./compute/lambda/get-reservation"
  environment                     = var.env
  role_arn                        = module.get_reservation_role.role_arn
  ecr_repository_url              = module.get_reservation_ecr.get_reservation_ecr_repository_url
  reservation_table_name          = module.reservation.table_name
  user_table_name                 = module.user.table_name
  region                          = var.aws_region
  tenant_table_name               = module.tenant.table_name
  location_table_name             = module.location.table_name
  location_id_index_name          = module.location.location_id_index_name
  reservation_link_key_secret_arn = module.reservation_secrets.link_signing_key_secret_arn
}
module "get_order_fn" {
  source                          = "./compute/lambda/get-order"
  environment                     = var.env
  role_arn                        = module.get_order_role.role_arn
  ecr_repository_url              = module.get_order_ecr.get_order_ecr_repository_url
  order_table_name                = module.order.table_name
  region                          = var.aws_region
  tenant_table_name               = module.tenant.table_name
  location_table_name             = module.location.table_name
  location_id_index_name          = module.location.location_id_index_name
  reservation_link_key_secret_arn = module.reservation_secrets.link_signing_key_secret_arn
  stripe_secret_arn               = module.platform_secrets.stripe_secret_arn
  stripe_api_version              = var.stripe_api_version
}
module "payment_intent_fn" {
  source                          = "./compute/lambda/payment-intent"
  environment                     = var.env
  privacy_env                     = local.privacy_env_consent
  role_arn                        = module.payment_intent_role.role_arn
  ecr_repository_url              = module.payment_intent_ecr.payment_intent_ecr_repository_url
  order_table_name                = module.order.table_name
  menu_table_name                 = module.menu.table_name
  stripe_secret_arn               = module.platform_secrets.stripe_secret_arn
  stripe_api_version              = var.stripe_api_version
  region                          = var.aws_region
  tenant_table_name               = module.tenant.table_name
  location_table_name             = module.location.table_name
  location_id_index_name          = module.location.location_id_index_name
  customer_site_url               = local.customer_site_url
  reservation_link_key_secret_arn = module.reservation_secrets.link_signing_key_secret_arn
  # Bot check on the order form only once the sites show the widget.
  turnstile_required       = var.turnstile_site_key != ""
  turnstile_secret_arn     = module.catering_secrets.turnstile_secret_arn
  request_guard_table_name = module.request_guard.table_name
  cloudfront_edge_secret   = random_password.cloudfront_edge.result
  marketing_table_name     = module.marketing.table_name
}
module "list_layout_version_fn" {
  source                               = "./compute/lambda/list-layout-version"
  environment                          = var.env
  role_arn                             = module.list_layout_version_role.role_arn
  ecr_repository_url                   = module.list_layout_version_ecr.list_layout_version_ecr_repository_url
  published_layout_snapshot_table_name = module.published_layout_snapshot.table_name
  region                               = var.aws_region
  tenant_table_name                    = module.tenant.table_name
  user_table_name                      = module.user.table_name
  location_table_name                  = module.location.table_name
  location_id_index_name               = module.location.location_id_index_name
}
module "manage_auth_fn" {
  source                   = "./compute/lambda/manage-auth"
  environment              = var.env
  role_arn                 = module.manage_auth_role.role_arn
  ecr_repository_url       = module.manage_auth_ecr.manage_auth_ecr_repository_url
  cognito_user_pool_id     = module.cognito.user_pool_id
  cognito_client_id        = module.cognito.user_pool_client_id
  cognito_client_secret    = module.cognito.user_pool_client_secret
  region                   = var.aws_region
  request_guard_table_name = module.request_guard.table_name
  cloudfront_edge_secret   = random_password.cloudfront_edge.result
  # Refresh cookie lifetime = the app client's refresh token validity.
  refresh_cookie_max_age = module.cognito.refresh_token_validity_hours * 3600
  # Local dev of the admin app (vite on :7070) may use the cookie routes
  # against the dev API. Never in prod.
  cookie_allowed_origins = var.env == "prod" ? "" : "http://localhost:7070"
}
module "manage_layout_element_fn" {
  source                         = "./compute/lambda/manage-layout-element"
  environment                    = var.env
  role_arn                       = module.manage_layout_element_role.role_arn
  ecr_repository_url             = module.manage_layout_element_ecr.manage_layout_element_ecr_repository_url
  live_layout_element_table_name = module.live_layout_element.table_name
  region                         = var.aws_region
  tenant_table_name              = module.tenant.table_name
  user_table_name                = module.user.table_name
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
  user_table_name                   = module.user.table_name
  location_table_name               = module.location.table_name
  location_id_index_name            = module.location.location_id_index_name
}
module "manage_order_fn" {
  source                          = "./compute/lambda/manage-order"
  environment                     = var.env
  role_arn                        = module.manage_order_role.role_arn
  ecr_repository_url              = module.manage_order_ecr.manage_order_ecr_repository_url
  order_table_name                = module.order.table_name
  customer_site_url               = local.customer_site_url
  user_table_name                 = module.user.table_name
  region                          = var.aws_region
  tenant_table_name               = module.tenant.table_name
  location_table_name             = module.location.table_name
  location_id_index_name          = module.location.location_id_index_name
  reservation_link_key_secret_arn = module.reservation_secrets.link_signing_key_secret_arn
  stripe_secret_arn               = module.platform_secrets.stripe_secret_arn
  stripe_api_version              = var.stripe_api_version
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
  source                               = "./compute/lambda/mark-arrived"
  environment                          = var.env
  privacy_env                          = local.privacy_env_mark_arrived
  role_arn                             = module.mark_arrived_role.role_arn
  ecr_repository_url                   = module.mark_arrived_ecr.mark_arrived_ecr_repository_url
  reservation_table_name               = module.reservation.table_name
  slot_occupancy_table_name            = module.slot_occupancy.table_name
  published_layout_snapshot_table_name = module.published_layout_snapshot.table_name
  user_table_name                      = module.user.table_name
  region                               = var.aws_region
  tenant_table_name                    = module.tenant.table_name
  location_table_name                  = module.location.table_name
  location_id_index_name               = module.location.location_id_index_name
  stripe_secret_arn                    = module.platform_secrets.stripe_secret_arn
  stripe_api_version                   = var.stripe_api_version
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
  privacy_env            = local.privacy_env_notification
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
  reservation_table_name               = module.reservation.table_name
  order_table_name                     = module.order.table_name
  catering_requests_table_name         = module.catering_requests.table_name
  reservation_link_key_secret_arn      = module.reservation_secrets.link_signing_key_secret_arn
  mail_outbox_bucket_name              = local.mail_outbox_bucket
  finance_table_name                   = module.finance.table_name
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
  source                   = "./compute/lambda/catering-settings"
  environment              = var.env
  role_arn                 = module.catering_settings_role.role_arn
  ecr_repository_url       = module.catering_settings_ecr.catering_settings_ecr_repository_url
  location_table_name      = module.location.table_name
  catering_menu_table_name = module.catering_menu.table_name
  region                   = var.aws_region
  tenant_table_name        = module.tenant.table_name
  location_id_index_name   = module.location.location_id_index_name
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
  privacy_env                        = local.privacy_env_consent
  role_arn                           = module.catering_requests_role.role_arn
  ecr_repository_url                 = module.catering_requests_ecr.catering_requests_ecr_repository_url
  catering_requests_table_name       = module.catering_requests.table_name
  location_table_name                = module.location.table_name
  catering_discount_tiers_table_name = module.catering_discount_tiers.table_name
  menu_table_name                    = module.menu.table_name
  catering_menu_table_name           = module.catering_menu.table_name
  region                             = var.aws_region

  catering_request_history_table_name = module.catering_request_history.table_name
  turnstile_secret_arn                = module.catering_secrets.turnstile_secret_arn
  link_signing_key_secret_arn         = module.catering_secrets.link_signing_key_secret_arn
  customer_site_url                   = local.customer_site_url
  tenant_table_name                   = module.tenant.table_name
  location_id_index_name              = module.location.location_id_index_name
  user_table_name                     = module.user.table_name
  request_guard_table_name            = module.request_guard.table_name
  # Bot check on the catering form only once the sites show the widget.
  turnstile_required     = var.turnstile_site_key != ""
  cloudfront_edge_secret = random_password.cloudfront_edge.result
  marketing_table_name   = module.marketing.table_name
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
  catering_menu_table_name            = module.catering_menu.table_name
  catering_documents_bucket_name      = module.catering_documents.bucket_name
  document_function_name              = "${module.catering_document_fn.function_name}:${module.catering_document_fn.alias_name}"
  stripe_secret_arn                   = module.platform_secrets.stripe_secret_arn
  stripe_api_version                  = var.stripe_api_version
  region                              = var.aws_region
  tenant_table_name                   = module.tenant.table_name
  location_id_index_name              = module.location.location_id_index_name
  user_table_name                     = module.user.table_name
  extra_env = merge(local.catering_document_lock_env, {
    SIGNING_PROVIDER_SECRET_ARN = module.catering_secrets.signing_provider_secret_arn
    SIGNING_WEBHOOK_URL         = local.catering_signing_webhook_url
    ADMIN_DASHBOARD_URL         = local.admin_app_url
  })
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
  cloudfront_edge_secret              = random_password.cloudfront_edge.result
  extra_env = merge(local.catering_document_lock_env, {
    REQUEST_GUARD_TABLE_NAME = module.request_guard.table_name
  })
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
  extra_env                           = local.catering_document_lock_env
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
  print_jobs_function_arn         = module.printing.alias_arns["print-jobs"]
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
# Deletes offboarded restaurants' data once purgeAt has passed
# (var.tenant_data_retention_days after offboarding).
module "tenant_purge_fn" {
  source                              = "./compute/lambda/tenant-purge"
  environment                         = var.env
  privacy_env                         = local.privacy_env_purge
  role_arn                            = module.tenant_purge_role.role_arn
  ecr_repository_url                  = module.tenant_purge_ecr.tenant_purge_ecr_repository_url
  scheduler_invoke_role_arn           = module.scheduler_invoke_tenant_purge_role.role_arn
  schedule_expression                 = var.tenant_purge_schedule
  retention_days                      = var.tenant_data_retention_days
  tenant_table_name                   = module.tenant.table_name
  location_table_name                 = module.location.table_name
  user_table_name                     = module.user.table_name
  user_tenant_index_name              = module.user.tenant_index_name
  tenant_user_pool_id                 = module.cognito.user_pool_id
  location_table_names                = [for k, t in local.tenant_purge_tables : t.name if !contains(["location", "catering_request_history", "marketing"], k)]
  catering_requests_table_name        = module.catering_requests.table_name
  catering_request_history_table_name = module.catering_request_history.table_name
  marketing_table_name                = module.marketing.table_name
  menu_image_bucket_name              = module.menu_image.bucket_name
  alert_topic_arn                     = module.alerts.topic_arn
  protected_zone_ids                  = local.platform_domain_enabled ? [module.platform_domain[0].zone_id] : []
}
module "platform_tenants_fn" {
  source                             = "./compute/lambda/platform-tenants"
  environment                        = var.env
  role_arn                           = module.platform_tenants_role.role_arn
  ecr_repository_url                 = module.platform_tenants_ecr.platform_tenants_ecr_repository_url
  tenant_table_name                  = module.tenant.table_name
  location_table_name                = module.location.table_name
  location_id_index_name             = module.location.location_id_index_name
  user_table_name                    = module.user.table_name
  user_tenant_index_name             = module.user.tenant_index_name
  tenant_user_pool_id                = module.cognito.user_pool_id
  owner_group_name                   = module.cognito.owner_group_name
  onboarding_state_machine_arn       = module.tenant_workflows.onboarding_state_machine_arn
  domain_attach_state_machine_arn    = module.tenant_workflows.domain_attach_state_machine_arn
  domain_detach_state_machine_arn    = module.tenant_workflows.domain_detach_state_machine_arn
  offboarding_state_machine_arn      = module.tenant_workflows.offboarding_state_machine_arn
  stripe_secret_arn                  = module.platform_secrets.stripe_secret_arn
  stripe_api_version                 = var.stripe_api_version
  platform_domain                    = local.tenant_sites_enabled ? var.platform_domain : "" # "" = custom domains refused (409)
  tenant_domain_cname_target         = local.tenant_domain_cname_target
  admin_app_url                      = local.admin_app_url
  platform_admin_app_url             = local.platform_admin_app_url
  region                             = var.aws_region
  operator_user_pool_id              = module.cognito_platform.user_pool_id
  operator_group_name                = module.cognito_platform.admin_group_name
  no_reply_email_address             = local.no_reply_email
  support_email_address              = var.support_email_address
  mail_outbox_bucket_name            = local.mail_outbox_bucket
  domain_provision_state_machine_arn = module.tenant_workflows.domain_provision_state_machine_arn
  domain_documents_bucket_name       = module.domain_documents.bucket_name
  finance_table_name                 = module.finance.table_name
  finance_rollup_alias_arn           = module.finance_rollup_fn.alias_arn
  site_analytics_table_name          = local.platform_domain_enabled ? module.site_analytics[0].table_name : ""
  alert_topic_arn                    = module.alerts.topic_arn
  billing_tax_rate_id                = module.billing_catalog.tax_rate_id
  billing_days_until_due             = var.billing_days_until_due
  billing_suspend_after_days         = var.billing_suspend_after_days
  billing_reminder_interval_days     = var.billing_reminder_interval_days
  billing_late_fee_sek               = var.billing_late_fee_sek
  billing_late_fee_after_days        = var.billing_late_fee_after_days
  billing_reference_rate_pct         = var.billing_reference_rate_pct
  billing_interest_margin_pct        = var.billing_interest_margin_pct
  billing_notice_months              = var.billing_notice_months
  billing_trial_months               = var.billing_trial_months
  sms_price_sek                      = var.sms_price_sek
  invoicing_schedule_expression      = var.billing_invoicing_schedule
  dunning_schedule_expression        = var.billing_dunning_schedule
  scheduler_invoke_role_arn          = module.scheduler_invoke_platform_tenants_role.role_arn
}
# Nightly figures for the Finance page (Cost Explorer, usage per customer,
# allocation). Booqy Console's Rebuild invokes it for a date range.
module "finance_rollup_fn" {
  source                    = "./compute/lambda/finance-rollup"
  environment               = var.env
  role_arn                  = module.finance_rollup_role.role_arn
  ecr_repository_url        = module.finance_rollup_ecr.finance_rollup_ecr_repository_url
  scheduler_invoke_role_arn = module.scheduler_invoke_finance_rollup_role.role_arn
  schedule_expression       = var.finance_rollup_schedule
  finance_table_name        = module.finance.table_name
  tenant_table_name         = module.tenant.table_name
  location_table_name       = module.location.table_name
  reservation_table_name    = module.reservation.table_name
  order_table_name          = module.order.table_name
  log_group_names           = local.tenant_aware_log_groups
  usd_to_sek                = var.aws_usd_to_sek
  cost_allocation           = var.cost_allocation
  sms_price_sek             = var.sms_price_sek
  alert_topic_arn           = module.alerts.topic_arn
}
# Nightly figures for Statistik in the admin app (per location and day).
module "insights_rollup_fn" {
  source                               = "./compute/lambda/insights-rollup"
  environment                          = var.env
  role_arn                             = module.insights_rollup_role.role_arn
  ecr_repository_url                   = module.insights_rollup_ecr.insights_rollup_ecr_repository_url
  scheduler_invoke_role_arn            = module.scheduler_invoke_insights_rollup_role.role_arn
  schedule_expression                  = var.insights_rollup_schedule
  insights_table_name                  = module.insights.table_name
  tenant_table_name                    = module.tenant.table_name
  location_table_name                  = module.location.table_name
  reservation_table_name               = module.reservation.table_name
  order_table_name                     = module.order.table_name
  catering_requests_table_name         = module.catering_requests.table_name
  published_layout_snapshot_table_name = module.published_layout_snapshot.table_name
  marketing_table_name                 = module.marketing.table_name
}
# GET /insights: Statistik's figures for a period.
module "insights_fn" {
  source                               = "./compute/lambda/insights"
  environment                          = var.env
  role_arn                             = module.insights_role.role_arn
  ecr_repository_url                   = module.insights_ecr.insights_ecr_repository_url
  insights_table_name                  = module.insights.table_name
  tenant_table_name                    = module.tenant.table_name
  location_table_name                  = module.location.table_name
  location_id_index_name               = module.location.location_id_index_name
  user_table_name                      = module.user.table_name
  reservation_table_name               = module.reservation.table_name
  order_table_name                     = module.order.table_name
  catering_requests_table_name         = module.catering_requests.table_name
  published_layout_snapshot_table_name = module.published_layout_snapshot.table_name
  marketing_table_name                 = module.marketing.table_name
}
module "tenant_account_fn" {
  source                 = "./compute/lambda/tenant-account"
  environment            = var.env
  role_arn               = module.tenant_account_role.role_arn
  ecr_repository_url     = module.tenant_account_ecr.tenant_account_ecr_repository_url
  tenant_table_name      = module.tenant.table_name
  location_table_name    = module.location.table_name
  user_table_name        = module.user.table_name
  stripe_secret_arn      = module.platform_secrets.stripe_secret_arn
  stripe_api_version     = var.stripe_api_version
  admin_app_url          = local.admin_app_url
  region                 = var.aws_region
  location_id_index_name = module.location.location_id_index_name
}
module "tenant_site_config_fn" {
  source                 = "./compute/lambda/tenant-site-config"
  environment            = var.env
  privacy_env            = local.retention_env
  role_arn               = module.tenant_site_config_role.role_arn
  ecr_repository_url     = module.tenant_site_config_ecr.tenant_site_config_ecr_repository_url
  tenant_table_name      = module.tenant.table_name
  location_table_name    = module.location.table_name
  turnstile_site_key     = var.turnstile_site_key
  stripe_publishable_key = var.stripe_publishable_key
  region                 = var.aws_region
  location_id_index_name = module.location.location_id_index_name
}
module "reservation_reminders_fn" {
  source                    = "./compute/lambda/reservation-reminders"
  environment               = var.env
  role_arn                  = module.reservation_reminders_role.role_arn
  ecr_repository_url        = module.reservation_reminders_ecr.reservation_reminders_ecr_repository_url
  scheduler_invoke_role_arn = module.scheduler_invoke_reservation_reminders_role.role_arn
  tenant_table_name         = module.tenant.table_name
  location_table_name       = module.location.table_name
  location_id_index_name    = module.location.location_id_index_name
  reservation_table_name    = module.reservation.table_name
  slot_occupancy_table_name = module.slot_occupancy.table_name
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
  finance_table_name         = module.finance.table_name
}


#Monitoring
module "alerts" {
  source = "./monitoring/alerts"
  # CloudFront metrics and their alarms live in us-east-1 (front-door.tf)
  providers = {
    aws           = aws
    aws.us_east_1 = aws.us_east_1
  }

  environment             = var.env
  region                  = var.aws_region
  alert_emails            = var.alert_emails
  dlq_queue_names         = module.dead_letter.queue_names
  replay_function_name    = module.dlq_replay_fn.function_name
  replay_interval_minutes = var.dlq_replay_interval_minutes

  sms_monthly_spend_limit_usd        = var.sms_monthly_spend_limit_usd
  sms_delivery_logging               = var.sms_delivery_logging
  sms_delivery_success_sampling_rate = var.sms_delivery_success_sampling_rate

  # Front door: API Gateway 5xx rate and p99 latency, CloudFront 5xx rate on
  # the admin, customer and (when on) tenant-sites distributions, and the
  # 5-minute uptime check of the customer site, the admin app and
  # GET /site-config - see docs/RELEASES.md.
  api_id       = module.api_gateway.api_id
  api_name     = module.api_gateway.api_name
  api_endpoint = module.api_gateway.api_endpoint
  cloudfront_distributions = merge(
    {
      admin    = module.cloudfront_private.distribution_id
      customer = module.cloudfront_public.distribution_id
    },
    local.tenant_sites_enabled ? { tenant-sites = module.platform_domain[0].multitenant_distribution_id } : {}
  )
  customer_site_url = var.smoke_test_host != "" ? "https://${var.smoke_test_host}" : local.customer_site_url
  admin_app_url     = local.admin_app_url
  smoke_test_host   = var.smoke_test_host
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
    (module.activate_layout_version_fn.function_name)     = { alias_name = module.activate_layout_version_fn.alias_name }
    (module.block_table_fn.function_name)                 = { alias_name = module.block_table_fn.alias_name }
    (module.cancel_reservation_fn.function_name)          = { alias_name = module.cancel_reservation_fn.alias_name }
    (module.catering_customer_fn.function_name)           = { alias_name = module.catering_customer_fn.alias_name }
    (module.catering_discount_tiers_fn.function_name)     = { alias_name = module.catering_discount_tiers_fn.alias_name }
    (module.catering_document_fn.function_name)           = { alias_name = module.catering_document_fn.alias_name }
    (module.catering_lifecycle_fn.function_name)          = { alias_name = module.catering_lifecycle_fn.alias_name }
    (module.catering_offer_fn.function_name)              = { alias_name = module.catering_offer_fn.alias_name }
    (module.catering_requests_fn.function_name)           = { alias_name = module.catering_requests_fn.alias_name }
    (module.catering_settings_fn.function_name)           = { alias_name = module.catering_settings_fn.alias_name }
    (module.catering_signing_webhook_fn.function_name)    = { alias_name = module.catering_signing_webhook_fn.alias_name }
    (module.catering_stripe_webhook_fn.function_name)     = { alias_name = module.catering_stripe_webhook_fn.alias_name }
    (module.create_location_fn.function_name)             = { alias_name = module.create_location_fn.alias_name }
    (module.create_pending_reservation_fn.function_name)  = { alias_name = module.create_pending_reservation_fn.alias_name }
    (module.dlq_replay_fn.function_name)                  = { alias_name = module.dlq_replay_fn.alias_name }
    (module.expire_layout_version_fn.function_name)       = { alias_name = module.expire_layout_version_fn.alias_name }
    (module.get_availability_fn.function_name)            = { alias_name = module.get_availability_fn.alias_name }
    (module.get_location_fn.function_name)                = { alias_name = module.get_location_fn.alias_name }
    (module.get_menu_fn.function_name)                    = { alias_name = module.get_menu_fn.alias_name }
    (module.get_order_fn.function_name)                   = { alias_name = module.get_order_fn.alias_name }
    (module.get_reservation_fn.function_name)             = { alias_name = module.get_reservation_fn.alias_name }
    (module.list_layout_version_fn.function_name)         = { alias_name = module.list_layout_version_fn.alias_name }
    (module.manage_auth_fn.function_name)                 = { alias_name = module.manage_auth_fn.alias_name }
    (module.manage_layout_element_fn.function_name)       = { alias_name = module.manage_layout_element_fn.alias_name }
    (module.manage_menu_fn.function_name)                 = { alias_name = module.manage_menu_fn.alias_name }
    (module.manage_order_fn.function_name)                = { alias_name = module.manage_order_fn.alias_name }
    (module.manage_user_fn.function_name)                 = { alias_name = module.manage_user_fn.alias_name }
    (module.mark_arrived_fn.function_name)                = { alias_name = module.mark_arrived_fn.alias_name }
    (module.no_show_check_fn.function_name)               = { alias_name = module.no_show_check_fn.alias_name }
    (module.notification_fn.function_name)                = { alias_name = module.notification_fn.alias_name }
    (module.payment_intent_fn.function_name)              = { alias_name = module.payment_intent_fn.alias_name }
    (module.platform_stripe_webhook_fn.function_name)     = { alias_name = module.platform_stripe_webhook_fn.alias_name }
    (module.platform_tenants_fn.function_name)            = { alias_name = module.platform_tenants_fn.alias_name }
    (module.pre_signed_url_fn.function_name)              = { alias_name = module.pre_signed_url_fn.alias_name }
    (module.publish_layout_fn.function_name)              = { alias_name = module.publish_layout_fn.alias_name }
    (module.reactivate_menu_item_fn.function_name)        = { alias_name = module.reactivate_menu_item_fn.alias_name }
    (module.stripe_webhook_fn.function_name)              = { alias_name = module.stripe_webhook_fn.alias_name }
    (module.tenant_account_fn.function_name)              = { alias_name = module.tenant_account_fn.alias_name }
    (module.tenant_purge_fn.function_name)                = { alias_name = module.tenant_purge_fn.alias_name }
    (module.data_retention_fn.function_name)              = { alias_name = module.data_retention_fn.alias_name }
    (module.guest_privacy_fn.function_name)               = { alias_name = module.guest_privacy_fn.alias_name }
    (module.finance_rollup_fn.function_name)              = { alias_name = module.finance_rollup_fn.alias_name }
    (module.insights_fn.function_name)                    = { alias_name = module.insights_fn.alias_name }
    (module.insights_rollup_fn.function_name)             = { alias_name = module.insights_rollup_fn.alias_name }
    (module.tenant_site_config_fn.function_name)          = { alias_name = module.tenant_site_config_fn.alias_name }
    (module.reservation_reminders_fn.function_name)       = { alias_name = module.reservation_reminders_fn.alias_name }
    (module.webhook_payment_intent_fn.function_name)      = { alias_name = module.webhook_payment_intent_fn.alias_name }
    (module.marketing.function_names["marketing"])        = { alias_name = module.marketing.alias_names["marketing"] }
    (module.marketing.function_names["marketing-public"]) = { alias_name = module.marketing.alias_names["marketing-public"] }
    (module.marketing.function_names["marketing-send"])   = { alias_name = module.marketing.alias_names["marketing-send"] }
    (module.marketing.function_names["marketing-sync"])   = { alias_name = module.marketing.alias_names["marketing-sync"] }
    (module.printing.function_names["print-jobs"])        = { alias_name = module.printing.alias_names["print-jobs"] }
    (module.printing.function_names["print-device"])      = { alias_name = module.printing.alias_names["print-device"] }
    (module.terminal.function_name)                       = { alias_name = module.terminal.alias_name }
    (module.kassa.function_name)                          = { alias_name = module.kassa.alias_name }
    (module.accounting.function_name)                     = { alias_name = module.accounting.alias_name }
  }
}


#API Gateway
module "api_gateway" {
  source      = "./network/api-gateway"
  environment = var.env
  # Owner privacy API (privacy-consent.tf, network/api-gateway/privacy-routes.tf)
  guest_privacy_invoke_arn    = module.guest_privacy_fn.alias_invoke_arn
  guest_privacy_function_name = module.guest_privacy_fn.function_name
  region                      = var.aws_region
  cognito_user_pool_id        = module.cognito.user_pool_id
  cognito_client_id           = module.cognito.user_pool_client_id
  # Tenant websites live on domains added at runtime - see the CORS note in
  # network/api-gateway (bearer tokens only, so "*" is safe here).
  allowed_origins                          = ["*"]
  platform_user_pool_id                    = module.cognito_platform.user_pool_id
  platform_client_id                       = module.cognito_platform.client_id
  platform_tenants_function_name           = module.platform_tenants_fn.function_name
  platform_tenants_invoke_arn              = module.platform_tenants_fn.alias_invoke_arn
  tenant_account_function_name             = module.tenant_account_fn.function_name
  tenant_account_invoke_arn                = module.tenant_account_fn.alias_invoke_arn
  insights_function_name                   = module.insights_fn.function_name
  insights_invoke_arn                      = module.insights_fn.alias_invoke_arn
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
  marketing_function_name                  = module.marketing.function_names["marketing"]
  marketing_invoke_arn                     = module.marketing.alias_invoke_arns["marketing"]
  marketing_public_function_name           = module.marketing.function_names["marketing-public"]
  marketing_public_invoke_arn              = module.marketing.alias_invoke_arns["marketing-public"]
  # Kitchen printing (printing-routes.tf)
  print_jobs_function_name   = module.printing.function_names["print-jobs"]
  print_jobs_invoke_arn      = module.printing.alias_invoke_arns["print-jobs"]
  print_device_function_name = module.printing.function_names["print-device"]
  print_device_invoke_arn    = module.printing.alias_invoke_arns["print-device"]
  # Card payments at the till (terminal.tf, network/api-gateway/terminal-routes.tf)
  terminal_payments_function_name = module.terminal.function_name
  terminal_payments_invoke_arn    = module.terminal.alias_invoke_arn
  # Kassa (kassa.tf, network/api-gateway/kassa-routes.tf)
  kassa_function_name = module.kassa.function_name
  kassa_invoke_arn    = module.kassa.alias_invoke_arn
  # Accounting export (accounting.tf, network/api-gateway/accounting-routes.tf)
  accounting_function_name = module.accounting.function_name
  accounting_invoke_arn    = module.accounting.alias_invoke_arn
}

# Marketing (plan feature "marketing"): visit statistics, attribution and
# email campaigns. Table, link key, functions, schedule, streams and SES
# events are all in ./marketing.
module "marketing" {
  source             = "./marketing"
  environment        = var.env
  consent_table_name = module.consent_log.table_name
  region             = var.aws_region
  ecr_repository_urls = {
    marketing          = module.marketing_ecr.repository_url
    "marketing-public" = module.marketing_public_ecr.repository_url
    "marketing-send"   = module.marketing_send_ecr.repository_url
    "marketing-sync"   = module.marketing_sync_ecr.repository_url
  }
  tenant_table_name      = module.tenant.table_name
  location_table_name    = module.location.table_name
  location_id_index_name = module.location.location_id_index_name
  user_table_name        = module.user.table_name
  user_table_arn         = module.user.table_arn
  menu_table_name        = module.menu.table_name
  menu_table_arn         = module.menu.table_arn
  # imageKey already starts with menu-images/, served by the public distribution.
  menu_image_base_url     = local.customer_site_url
  customer_site_url       = local.customer_site_url
  admin_app_url           = local.admin_app_url
  reservation_table_name  = module.reservation.table_name
  reservation_stream_arn  = module.reservation.stream_arn
  order_table_name        = module.order.table_name
  order_stream_arn        = module.order.stream_arn
  ses_identity_arn        = local.ses_identity_arn
  from_address            = local.no_reply_email
  mail_outbox_bucket_name = local.mail_outbox_bucket
  mail_outbox_bucket_arn  = local.mail_outbox_arn
  finance_table_name      = module.finance.table_name
  finance_table_arn       = module.finance.table_arn
  # Welcome offer sign-up: the same bot check and attempt counters as the
  # booking and order forms.
  turnstile_required       = var.turnstile_site_key != ""
  turnstile_secret_arn     = module.catering_secrets.turnstile_secret_arn
  request_guard_table_name = module.request_guard.table_name
  request_guard_table_arn  = module.request_guard.table_arn
  # Discount codes at checkout and the catering form's opt-in write to the
  # marketing table: a policy on those functions' roles.
  payment_intent_role_name    = module.payment_intent_role.role_name
  catering_requests_role_name = module.catering_requests_role.role_name
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
  terminal_webhook_url    = module.terminal.webhook_url
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
  # Restaurant websites on their own domains - a separate switch, so the
  # domain can serve only restaurant./admin./mail. <slug>.<domain> on top of
  # that is var.tenant_subdomains_enabled.
  tenant_sites_enabled      = local.platform_domain_enabled && var.tenant_sites_enabled
  tenant_subdomains_enabled = local.tenant_sites_enabled && var.tenant_subdomains_enabled

  # restaurang.<domain> = restaurant admin app, admin.<domain> = Booqy Console.
  # restaurant.<domain> was the admin app's first name: it stays an alias of
  # the same distribution and redirects (301) to restaurang.<domain>, so old
  # bookmarks and the /api links in emails already sent keep working.
  admin_app_hostname        = "restaurang.${var.platform_domain}"
  legacy_admin_app_hostname = "restaurant.${var.platform_domain}"
  platform_admin_hostname   = "admin.${var.platform_domain}"
  admin_app_url             = local.platform_domain_enabled ? "https://${local.admin_app_hostname}" : "https://${module.cloudfront_private.distribution_domain_name}"
  platform_admin_app_url    = local.platform_domain_enabled ? "https://${local.platform_admin_hostname}" : "https://${module.cloudfront_platform_admin.distribution_domain_name}"
  # Every origin the operator app may sign in from (OAuth callback URLs).
  platform_admin_app_urls = distinct(concat(
    ["https://${module.cloudfront_platform_admin.distribution_domain_name}"],
    local.platform_domain_enabled ? ["https://${local.platform_admin_hostname}"] : [],
    var.env == "prod" ? [] : ["http://localhost:5173"],
  ))

  # One sender for all tenants (their name goes in the display name, their
  # address in Reply-To): mail.<platform domain> once it exists.
  no_reply_email        = local.platform_domain_enabled ? module.platform_domain[0].no_reply_address : var.no_reply_email_address
  mail_outbox_enabled   = var.mail_outbox && var.env != "prod"
  mail_outbox_bucket    = local.mail_outbox_enabled ? module.mail_outbox[0].bucket_name : ""
  mail_outbox_arn       = local.mail_outbox_enabled ? module.mail_outbox[0].bucket_arn : ""
  no_reply_from_address = local.no_reply_email
  ses_identity_arn      = local.platform_domain_enabled ? module.platform_domain[0].ses_identity_arn : module.ses.identity_arn

  # Every table tenant-purge deletes a restaurant's partitions from. All but
  # the last three are keyed LOCATION#<locationId>. Add a new tenant table
  # here (and to functions/tenant-purge) or offboarded data stays behind.
  tenant_purge_tables = {
    reservation               = { name = module.reservation.table_name, arn = module.reservation.table_arn }
    slot_occupancy            = { name = module.slot_occupancy.table_name, arn = module.slot_occupancy.table_arn }
    order                     = { name = module.order.table_name, arn = module.order.table_arn }
    menu                      = { name = module.menu.table_name, arn = module.menu.table_arn }
    live_layout_element       = { name = module.live_layout_element.table_name, arn = module.live_layout_element.table_arn }
    published_layout_snapshot = { name = module.published_layout_snapshot.table_name, arn = module.published_layout_snapshot.table_arn }
    catering_requests         = { name = module.catering_requests.table_name, arn = module.catering_requests.table_arn }
    insights                  = { name = module.insights.table_name, arn = module.insights.table_arn }
    catering_discount_tiers   = { name = module.catering_discount_tiers.table_name, arn = module.catering_discount_tiers.table_arn }
    catering_menu             = { name = module.catering_menu.table_name, arn = module.catering_menu.table_arn }
    location                  = { name = module.location.table_name, arn = module.location.table_arn }
    catering_request_history  = { name = module.catering_request_history.table_name, arn = module.catering_request_history.table_arn }
    marketing                 = { name = module.marketing.table_name, arn = module.marketing.table_arn }
    print                     = { name = module.print.table_name, arn = module.print.table_arn }
  }

  tenant_domain_cname_target = local.tenant_sites_enabled ? module.platform_domain[0].cname_target : ""

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
    insights                   = module.insights_role.role_name
    reservation_reminders      = module.reservation_reminders_role.role_name
    webhook_payment_intent     = module.webhook_payment_intent_role.role_name
    marketing                  = module.marketing.role_names["marketing"]
    marketing_public           = module.marketing.role_names["marketing-public"]
    marketing_send             = module.marketing.role_names["marketing-send"]
    marketing_sync             = module.marketing.role_names["marketing-sync"]
    print_jobs                 = module.printing.role_names["print-jobs"]
    print_device               = module.printing.role_names["print-device"]
    terminal_payments          = module.terminal.role_name
    kassa                      = module.kassa.role_name
    accounting                 = module.accounting.role_name
  }

  # Log groups finance-rollup counts API requests in: every Lambda that
  # resolves a tenant (shared/tenant.py logs one line per request).
  tenant_aware_log_groups = [
    for name in keys(local.tenant_aware_role_names) :
    "/aws/lambda/${var.env == "prod" ? "" : "${var.env}-"}${replace(name, "_", "-")}"
  ]
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
  subdomain_delegations                   = var.platform_subdomain_delegations
  tenant_sites_enabled                    = var.tenant_sites_enabled
  tenant_subdomains_enabled               = var.tenant_subdomains_enabled
  customer_bucket_regional_domain_name    = module.customer_front_end_asset.bucket_regional_domain_name
  menu_image_bucket_regional_domain_name  = module.menu_image.bucket_regional_domain_name
  admin_distribution_domain_name          = module.cloudfront_private.distribution_domain_name
  admin_app_hostname                      = local.admin_app_hostname
  legacy_admin_app_hostname               = local.legacy_admin_app_hostname
  platform_admin_hostname                 = local.platform_admin_hostname
  platform_admin_distribution_domain_name = module.cloudfront_platform_admin.distribution_domain_name
  demo_request_enabled                    = true
  demo_request_origin_domain              = module.demo_request_fn[0].function_url_domain
  site_analytics_enabled                  = true
  site_analytics_origin_domain            = module.site_analytics[0].function_url_domain
  site_response_headers_policy_id         = module.cloudfront_public.site_response_headers_policy_id
  dmarc_report_address                    = var.dmarc_report_address
}

# Adopt an existing hosted zone for the platform domain (var.platform_domain_zone_id)
# instead of creating a second one: no name server change at the registrar, and
# dev's zone can be delegated from prod before the certificate needs it. A no-op
# once the zone is in state.
import {
  for_each = local.platform_domain_enabled && var.platform_domain_zone_id != "" ? toset([var.platform_domain_zone_id]) : toset([])
  to       = module.platform_domain[0].aws_route53_zone.platform
  id       = each.value
}

# --- Control plane workflows --------------------------------------------------------
data "aws_caller_identity" "current" {}

module "tenant_workflows" {
  source = "./orchestration/tenant-workflows"

  environment               = var.env
  region                    = var.aws_region
  tenant_table_name         = module.tenant.table_name
  tenant_table_arn          = module.tenant.table_arn
  user_table_name           = module.user.table_name
  user_table_arn            = module.user.table_arn
  user_tenant_index_name    = module.user.tenant_index_name
  tenant_user_pool_id       = module.cognito.user_pool_id
  tenant_user_pool_arn      = module.cognito.user_pool_arn
  owner_group_name          = module.cognito.owner_group_name
  stripe_secret_key         = var.stripe_secret_key
  stripe_api_version        = var.stripe_api_version
  default_tax_rates         = var.default_tax_rates
  alert_topic_arn           = module.alerts.topic_arn
  platform_domain_enabled   = local.tenant_sites_enabled
  tenant_subdomains_enabled = local.tenant_subdomains_enabled
  platform_domain           = local.tenant_sites_enabled ? var.platform_domain : ""

  multitenant_distribution_id  = local.tenant_sites_enabled ? module.platform_domain[0].multitenant_distribution_id : ""
  multitenant_distribution_arn = local.tenant_sites_enabled ? module.platform_domain[0].multitenant_distribution_arn : ""
  connection_group_id          = local.tenant_sites_enabled ? module.platform_domain[0].connection_group_id : ""
  connection_group_arn         = local.tenant_sites_enabled ? module.platform_domain[0].connection_group_arn : ""
  cname_target                 = local.tenant_domain_cname_target
  # The function's live alias, by name: the function's environment holds
  # this module's state machine ARNs, so referencing it would be a cycle.
  tenant_data_retention_days    = var.tenant_data_retention_days
  platform_tenants_function_arn = "arn:aws:lambda:${var.aws_region}:${data.aws_caller_identity.current.account_id}:function:${var.env == "prod" ? "platform-tenants" : "${var.env}-platform-tenants"}:live"
}

#CloudFront
module "cloudfront_public" {
  source                                 = "./network/cloudfront/public"
  environment                            = var.env
  customer_bucket_regional_domain_name   = module.customer_front_end_asset.bucket_regional_domain_name
  menu_image_bucket_regional_domain_name = module.menu_image.bucket_regional_domain_name
}
# Shared secret the admin app's CloudFront sends to the API with every /api
# request (origin header x-booqy-edge). The API trusts the viewer IP and
# host headers only when it matches. Not an IAM credential; rotating it is
# a terraform apply (taint this resource).
resource "random_password" "cloudfront_edge" {
  length  = 48
  special = false
}

module "cloudfront_private" {
  source                                 = "./network/cloudfront/private"
  environment                            = var.env
  admin_bucket_regional_domain_name      = module.admin_front_end_asset.bucket_regional_domain_name
  menu_image_bucket_regional_domain_name = module.menu_image.bucket_regional_domain_name
  aliases                                = local.platform_domain_enabled ? [local.admin_app_hostname, local.legacy_admin_app_hostname] : []
  canonical_host                         = local.platform_domain_enabled ? local.admin_app_hostname : ""
  legacy_hosts                           = local.platform_domain_enabled ? [local.legacy_admin_app_hostname] : []
  acm_certificate_arn                    = local.platform_domain_enabled ? module.platform_domain[0].certificate_arn : ""
  # From the API's id, not its stage URL: the stage waits for routes and
  # their Lambdas, some of which take the admin app's URL (a cycle).
  api_origin_domain = "${module.api_gateway.api_id}.execute-api.${var.aws_region}.amazonaws.com"
  edge_secret       = random_password.cloudfront_edge.result
}
# Operator app (platform admin) - where tenants are created and managed
module "cloudfront_platform_admin" {
  source                      = "./network/cloudfront/platform-admin"
  environment                 = var.env
  bucket_regional_domain_name = module.platform_admin_front_end_asset.bucket_regional_domain_name
  aliases                     = local.platform_domain_enabled ? [local.platform_admin_hostname] : []
  acm_certificate_arn         = local.platform_domain_enabled ? module.platform_domain[0].certificate_arn : ""
  # The Console's CSP: it talks to the operator user pool (Amplify SRP) and
  # the API directly. From the API's id (see cloudfront_private).
  api_origin = "https://${module.api_gateway.api_id}.execute-api.${var.aws_region}.amazonaws.com"
  region     = var.aws_region
  # DomainWizard posts domain-transfer PDFs straight to this bucket
  upload_bucket_name = module.domain_documents.bucket_name
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
# "Boka en demo" form on the public page: <platform_domain>/api/demo-request
# -> demo-request Lambda (zip from this repo) -> email to var.demo_request_recipient.
module "demo_request_role" {
  count            = local.platform_domain_enabled ? 1 : 0
  source           = "./security/iam/demo-request"
  environment      = var.env
  region           = var.aws_region
  ses_identity_arn = local.ses_identity_arn
  from_address     = local.no_reply_email
}
module "demo_request_fn" {
  count        = local.platform_domain_enabled ? 1 : 0
  source       = "./compute/lambda/demo-request"
  environment  = var.env
  role_arn     = module.demo_request_role[0].role_arn
  recipient    = var.demo_request_recipient
  from_address = local.no_reply_email
}
# Only the landing distribution may call the function URL (AWS_IAM + OAC).
# Function URLs need both permissions for the CloudFront service principal.
resource "aws_lambda_permission" "demo_request_url" {
  count                  = local.platform_domain_enabled ? 1 : 0
  statement_id           = "AllowLandingCloudFrontInvokeUrl"
  action                 = "lambda:InvokeFunctionUrl"
  function_name          = module.demo_request_fn[0].function_name
  qualifier              = module.demo_request_fn[0].alias_name
  principal              = "cloudfront.amazonaws.com"
  source_arn             = module.platform_domain[0].landing_distribution_arn
  function_url_auth_type = "AWS_IAM"
}
resource "aws_lambda_permission" "demo_request_invoke" {
  count         = local.platform_domain_enabled ? 1 : 0
  statement_id  = "AllowLandingCloudFrontInvoke"
  action        = "lambda:InvokeFunction"
  function_name = module.demo_request_fn[0].function_name
  qualifier     = module.demo_request_fn[0].alias_name
  principal     = "cloudfront.amazonaws.com"
  source_arn    = module.platform_domain[0].landing_distribution_arn
}

# Cookieless statistics for the public page (<platform_domain>/api/collect),
# shown on Booqy Console's Website page. Feature-scoped in site-analytics/.
module "site_analytics" {
  count                    = local.platform_domain_enabled ? 1 : 0
  source                   = "./site-analytics"
  environment              = var.env
  region                   = var.aws_region
  site                     = var.platform_domain
  landing_distribution_arn = module.platform_domain[0].landing_distribution_arn
  console_role_name        = module.platform_tenants_role.role_name
  alert_topic_arn          = module.alerts.topic_arn
}

# The public page on <platform_domain> (booqy-website repo) - its own bucket
# and distribution, nothing else.
module "website_deploy_role" {
  count                       = local.platform_domain_enabled ? 1 : 0
  source                      = "./security/iam/oidc/website-deploy-role"
  environment                 = var.env
  oidc_provider_arn           = module.github_oidc_provider.provider_arn
  github_repo                 = "${var.github_org}@*/${var.website_repo}"
  website_bucket_arn          = module.platform_domain[0].landing_bucket_arn
  cloudfront_distribution_arn = module.platform_domain[0].landing_distribution_arn
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
