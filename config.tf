
terraform {
  required_version = ">=1.14.0, < 2.0.0"
  backend "s3" {}

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
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
  notification_lambda_arn = module.notification_fn.function_arn
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


#S3 Buckets
module "menu_image" {
  source                              = "./storage/s3/menu-image"
  environment                         = var.env
  public_cloudfront_distribution_arn  = module.cloudfront_public.distribution_arn
  private_cloudfront_distribution_arn = module.cloudfront_private.distribution_arn
}
module "customer_front_end_asset" {
  source                      = "./storage/s3/customer-front-end-asset"
  environment                 = var.env
  cloudfront_distribution_arn = module.cloudfront_public.distribution_arn
}
module "admin_front_end_asset" {
  source                      = "./storage/s3/admin-front-end-asset"
  environment                 = var.env
  cloudfront_distribution_arn = module.cloudfront_private.distribution_arn
}


#Cognito
module "cognito" {
  source      = "./storage/cognito"
  environment = var.env
}


#Network
module "ses" {
  source                 = "./network/ses"
  no_reply_email_address = var.no_reply_email_address
}


#IAM Security
module "get_menu_role" {
  source         = "./security/iam/get-menu"
  environment    = var.env
  menu_table_arn = module.menu.table_arn
  region         = var.aws_region
}
module "manage_menu_role" {
  source         = "./security/iam/manage-menu"
  environment    = var.env
  menu_table_arn = module.menu.table_arn
  region         = var.aws_region
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
}
module "cancel_reservation_role" {
  source                   = "./security/iam/cancel-reservation"
  environment              = var.env
  location_table_arn       = module.location.table_arn
  slot_occupancy_table_arn = module.slot_occupancy.table_arn
  reservation_table_arn    = module.reservation.table_arn
  region                   = var.aws_region
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
  region                        = var.aws_region
}
module "block_table_role" {
  source                   = "./security/iam/block-table"
  environment              = var.env
  location_table_arn       = module.location.table_arn
  user_table_arn           = module.user.table_arn
  slot_occupancy_table_arn = module.slot_occupancy.table_arn
  region                   = var.aws_region
}
module "notification_role" {
  source                 = "./security/iam/notification"
  environment            = var.env
  reservation_stream_arn = module.reservation.stream_arn
  ses_identity_arn       = module.ses.identity_arn
  region                 = var.aws_region
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


#Compute
module "activate_layout_version_fn" {
  source                               = "./compute/lambda/activate-layout-version"
  environment                          = var.env
  role_arn                             = module.activate_layout_version_role.role_arn
  ecr_repository_url                   = module.activate_layout_version_ecr.activate_layout_version_ecr_repository_url
  published_layout_snapshot_table_name = module.published_layout_snapshot.table_name
  scheduler_invoke_role_arn            = module.scheduler_invoke_expire_layout_version_role.role_arn
  expire_layout_version_function_arn   = module.expire_layout_version_fn.function_arn
  region                               = var.aws_region
}
module "expire_layout_version_fn" {
  source                               = "./compute/lambda/expire-layout-version"
  environment                          = var.env
  role_arn                             = module.expire_layout_version_role.role_arn
  ecr_repository_url                   = module.expire_layout_version_ecr.expire_layout_version_ecr_repository_url
  published_layout_snapshot_table_name = module.published_layout_snapshot.table_name
  region                               = var.aws_region
}
module "block_table_fn" {
  source                    = "./compute/lambda/block-table"
  environment               = var.env
  role_arn                  = module.block_table_role.role_arn
  ecr_repository_url        = module.block_table_ecr.block_table_ecr_repository_url
  location_table_name       = module.location.table_name
  user_table_name           = module.user.table_name
  slot_occupancy_table_name = module.slot_occupancy.table_name
  region                    = var.aws_region
}
module "cancel_reservation_fn" {
  source                    = "./compute/lambda/cancel-reservation"
  environment               = var.env
  role_arn                  = module.cancel_reservation_role.role_arn
  ecr_repository_url        = module.cancel_reservation_ecr.cancel_reservation_ecr_repository_url
  location_table_name       = module.location.table_name
  slot_occupancy_table_name = module.slot_occupancy.table_name
  reservation_table_name    = module.reservation.table_name
  stripe_secret_key         = var.stripe_secret_key
  region                    = var.aws_region
}
module "create_location_fn" {
  source              = "./compute/lambda/create-location"
  environment         = var.env
  role_arn            = module.create_location_role.role_arn
  ecr_repository_url  = module.create_location_ecr.create_location_ecr_repository_url
  location_table_name = module.location.table_name
  region              = var.aws_region
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
  region                               = var.aws_region
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
}
module "get_location_fn" {
  source              = "./compute/lambda/get-location"
  environment         = var.env
  role_arn            = module.get_location_role.role_arn
  ecr_repository_url  = module.get_location_ecr.get_location_ecr_repository_url
  location_table_name = module.location.table_name
  region              = var.aws_region
}
module "get_menu_fn" {
  source             = "./compute/lambda/get-menu"
  environment        = var.env
  role_arn           = module.get_menu_role.role_arn
  ecr_repository_url = module.get_menu_ecr.get_menu_ecr_repository_url
  menu_table_name    = module.menu.table_name
  region             = var.aws_region
}
module "get_reservation_fn" {
  source                 = "./compute/lambda/get-reservation"
  environment            = var.env
  role_arn               = module.get_reservation_role.role_arn
  ecr_repository_url     = module.get_reservation_ecr.get_reservation_ecr_repository_url
  reservation_table_name = module.reservation.table_name
  region                 = var.aws_region
}
module "list_layout_version_fn" {
  source                               = "./compute/lambda/list-layout-version"
  environment                          = var.env
  role_arn                             = module.list_layout_version_role.role_arn
  ecr_repository_url                   = module.list_layout_version_ecr.list_layout_version_ecr_repository_url
  published_layout_snapshot_table_name = module.published_layout_snapshot.table_name
  region                               = var.aws_region
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
}
module "manage_menu_fn" {
  source             = "./compute/lambda/manage-menu"
  environment        = var.env
  role_arn           = module.manage_menu_role.role_arn
  ecr_repository_url = module.manage_menu_ecr.manage_menu_ecr_repository_url
  menu_table_name    = module.menu.table_name
  region             = var.aws_region
}
module "manage_user_fn" {
  source               = "./compute/lambda/manage-user"
  environment          = var.env
  role_arn             = module.manage_user_role.role_arn
  ecr_repository_url   = module.manage_user_ecr.manage_user_ecr_repository_url
  user_table_name      = module.user.table_name
  cognito_user_pool_id = module.cognito.user_pool_id
  region               = var.aws_region
}
module "mark_arrived_fn" {
  source                 = "./compute/lambda/mark-arrived"
  environment            = var.env
  role_arn               = module.mark_arrived_role.role_arn
  ecr_repository_url     = module.mark_arrived_ecr.mark_arrived_ecr_repository_url
  reservation_table_name = module.reservation.table_name
  region                 = var.aws_region
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
}
module "notification_fn" {
  source                 = "./compute/lambda/notification"
  environment            = var.env
  role_arn               = module.notification_role.role_arn
  ecr_repository_url     = module.notification_ecr.notification_ecr_repository_url
  no_reply_email_address = var.no_reply_email_address
  region                 = var.aws_region
}
module "pre_signed_url_fn" {
  source                  = "./compute/lambda/pre-signed-url"
  environment             = var.env
  role_arn                = module.pre_signed_url_role.role_arn
  ecr_repository_url      = module.pre_signed_url_ecr.pre_signed_url_ecr_repository_url
  menu_images_bucket_name = module.menu_image.bucket_name
  region                  = var.aws_region
}
module "publish_layout_fn" {
  source                               = "./compute/lambda/publish-layout"
  environment                          = var.env
  role_arn                             = module.publish_layout_role.role_arn
  ecr_repository_url                   = module.publish_layout_ecr.publish_layout_ecr_repository_url
  live_layout_element_table_name       = module.live_layout_element.table_name
  published_layout_snapshot_table_name = module.published_layout_snapshot.table_name
  region                               = var.aws_region
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
  no_show_check_function_arn     = module.no_show_check_fn.function_arn
  region                         = var.aws_region
  stripe_webhook_secret          = var.stripe_webhook_secret
}


#API Gateway
module "api_gateway" {
  source               = "./network/api-gateway"
  environment          = var.env
  region               = var.aws_region
  cognito_user_pool_id = module.cognito.user_pool_id
  cognito_client_id    = module.cognito.user_pool_client_id
  allowed_origins = [
    "https://${module.cloudfront_public.distribution_domain_name}",
    "https://${module.cloudfront_private.distribution_domain_name}",
  ]
  get_location_function_name               = module.get_location_fn.function_name
  get_location_invoke_arn                  = module.get_location_fn.invoke_arn
  create_location_function_name            = module.create_location_fn.function_name
  create_location_invoke_arn               = module.create_location_fn.invoke_arn
  get_menu_function_name                   = module.get_menu_fn.function_name
  get_menu_invoke_arn                      = module.get_menu_fn.invoke_arn
  manage_menu_function_name                = module.manage_menu_fn.function_name
  manage_menu_invoke_arn                   = module.manage_menu_fn.invoke_arn
  get_availability_function_name           = module.get_availability_fn.function_name
  get_availability_invoke_arn              = module.get_availability_fn.invoke_arn
  create_pending_reservation_function_name = module.create_pending_reservation_fn.function_name
  create_pending_reservation_invoke_arn    = module.create_pending_reservation_fn.invoke_arn
  get_reservation_function_name            = module.get_reservation_fn.function_name
  get_reservation_invoke_arn               = module.get_reservation_fn.invoke_arn
  cancel_reservation_function_name         = module.cancel_reservation_fn.function_name
  cancel_reservation_invoke_arn            = module.cancel_reservation_fn.invoke_arn
  mark_arrived_function_name               = module.mark_arrived_fn.function_name
  mark_arrived_invoke_arn                  = module.mark_arrived_fn.invoke_arn
  block_table_function_name                = module.block_table_fn.function_name
  block_table_invoke_arn                   = module.block_table_fn.invoke_arn
  manage_layout_element_function_name      = module.manage_layout_element_fn.function_name
  manage_layout_element_invoke_arn         = module.manage_layout_element_fn.invoke_arn
  publish_layout_function_name             = module.publish_layout_fn.function_name
  publish_layout_invoke_arn                = module.publish_layout_fn.invoke_arn
  list_layout_version_function_name        = module.list_layout_version_fn.function_name
  list_layout_version_invoke_arn           = module.list_layout_version_fn.invoke_arn
  activate_layout_version_function_name    = module.activate_layout_version_fn.function_name
  activate_layout_version_invoke_arn       = module.activate_layout_version_fn.invoke_arn
  manage_auth_function_name                = module.manage_auth_fn.function_name
  manage_auth_invoke_arn                   = module.manage_auth_fn.invoke_arn
  manage_user_function_name                = module.manage_user_fn.function_name
  manage_user_invoke_arn                   = module.manage_user_fn.invoke_arn
  pre_signed_url_function_name             = module.pre_signed_url_fn.function_name
  pre_signed_url_invoke_arn                = module.pre_signed_url_fn.invoke_arn
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
module "back_end_role" {
  source            = "./security/iam/oidc/back-end-role"
  environment       = var.env
  oidc_provider_arn = module.github_oidc_provider.provider_arn
  github_repo       = "${var.github_org}@*/${var.backend_repo}"
  region            = var.aws_region
}
