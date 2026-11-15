output "main_zone_id" {
  description = "Zone of test.<domain>"
  value       = aws_route53_zone.main.zone_id
}

output "dev_zone_id" {
  description = "Zone of test-dev.<domain>"
  value       = aws_route53_zone.dev.zone_id
}

output "zone_ids" {
  description = "Both test zones (never changed by tenant code: platform-tenants and tenant-purge deny them)"
  value       = [aws_route53_zone.main.zone_id, aws_route53_zone.dev.zone_id]
}

output "main_name_servers" {
  description = "Name servers of test.<domain>: prod.tfvars platform_subdomain_delegations[\"test\"]"
  value       = aws_route53_zone.main.name_servers
}

output "dev_name_servers" {
  description = "Name servers of test-dev.<domain>: prod.tfvars platform_subdomain_delegations[\"test-dev\"]"
  value       = aws_route53_zone.dev.name_servers
}

output "bucket_name" {
  description = "Sandbox bucket (main|dev/sites/<tenantId>/); empty until phase 2"
  value       = var.enabled ? aws_s3_bucket.sites[0].bucket : ""
}

output "bucket_arn" {
  description = "Sandbox bucket ARN; empty until phase 2"
  value       = var.enabled ? aws_s3_bucket.sites[0].arn : ""
}

output "distribution_id" {
  description = "Sandbox multi-tenant distribution; empty until phase 2"
  value       = var.enabled ? aws_cloudfront_multitenant_distribution.sites[0].id : ""
}

output "distribution_arn" {
  description = "Sandbox multi-tenant distribution ARN; empty until phase 2"
  value       = var.enabled ? aws_cloudfront_multitenant_distribution.sites[0].arn : ""
}

output "connection_group_id" {
  description = "Sandbox connection group; empty until phase 2"
  value       = var.enabled ? aws_cloudfront_connection_group.sites[0].id : ""
}

output "connection_group_arn" {
  description = "Sandbox connection group ARN; empty until phase 2"
  value       = var.enabled ? aws_cloudfront_connection_group.sites[0].arn : ""
}

output "routing_endpoint" {
  description = "Where both wildcards point"
  value       = var.enabled ? aws_cloudfront_connection_group.sites[0].routing_endpoint : ""
}

output "deploy_boundary_arn" {
  description = "Permissions boundary of every test site deploy role; empty until phase 2"
  value       = var.enabled ? aws_iam_policy.deploy_boundary[0].arn : ""
}
