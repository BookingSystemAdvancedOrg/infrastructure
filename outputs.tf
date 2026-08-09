output "stripe_webhook_url" {
  description = "Public HTTPS endpoint for StripeWebhookFn - after apply, register this as the webhook destination in the Stripe Dashboard (Developers > Webhooks) for this environment"
  value       = module.stripe_webhook_fn.function_url
}

output "api_endpoint" {
  description = "Base invoke URL of the HTTP API - what the front-end calls for every route except the Stripe webhook"
  value       = module.api_gateway.api_endpoint
}

output "customer_site_domain" {
  description = "Default *.cloudfront.net domain the customer-facing site is reachable at until a custom domain is wired up"
  value       = module.cloudfront_public.distribution_domain_name
}

output "admin_site_domain" {
  description = "Default *.cloudfront.net domain the staff/owner/super-user admin site is reachable at until a custom domain is wired up"
  value       = module.cloudfront_private.distribution_domain_name
}

# Function name -> ECR repository URL (no tag), for all 20 Lambda container
# image repos. Read by the CI pipeline (reusable_cicd.yml) after the
# ECR-only targeted apply, to find any repository that doesn't have a
# ":latest" image yet and push a placeholder image to it before the full
# apply runs - `aws_lambda_function` with package_type = "Image" fails to
# create if no image exists at the referenced tag yet.
#
# NOTE: if you add a new Lambda function, add its ECR module's output here
# AND add a matching -target=module.<name>_ecr to the "Terraform apply (ECR
# repositories only)" step in reusable_cicd.yml - both lists are manually
# kept in sync, Terraform has no way to derive either automatically.
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
    get_reservation            = module.get_reservation_ecr.get_reservation_ecr_repository_url
    list_layout_version        = module.list_layout_version_ecr.list_layout_version_ecr_repository_url
    manage_auth                = module.manage_auth_ecr.manage_auth_ecr_repository_url
    manage_layout_element      = module.manage_layout_element_ecr.manage_layout_element_ecr_repository_url
    manage_menu                = module.manage_menu_ecr.manage_menu_ecr_repository_url
    manage_user                = module.manage_user_ecr.manage_user_ecr_repository_url
    mark_arrived               = module.mark_arrived_ecr.mark_arrived_ecr_repository_url
    no_show_check              = module.no_show_check_ecr.no_show_check_ecr_repository_url
    notification               = module.notification_ecr.notification_ecr_repository_url
    pre_signed_url             = module.pre_signed_url_ecr.pre_signed_url_ecr_repository_url
    publish_layout             = module.publish_layout_ecr.publish_layout_ecr_repository_url
    stripe_webhook             = module.stripe_webhook_ecr.stripe_webhook_ecr_repository_url
  }
}
