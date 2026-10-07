output "zone_id" {
  description = "Route 53 hosted zone ID of the platform domain"
  value       = aws_route53_zone.platform.zone_id
}

output "name_servers" {
  description = "Name servers to delegate the platform domain to (NS records at the registrar / parent zone)"
  value       = aws_route53_zone.platform.name_servers
}

output "certificate_arn" {
  description = "ARN of the validated *.<domain> certificate (us-east-1) for the app./ops. aliases"
  value       = aws_acm_certificate_validation.wildcard.certificate_arn
}

output "multitenant_distribution_id" {
  description = "ID of the tenant-sites multi-tenant distribution"
  value       = aws_cloudfront_multitenant_distribution.tenants.id
}

output "multitenant_distribution_arn" {
  description = "ARN of the tenant-sites multi-tenant distribution"
  value       = aws_cloudfront_multitenant_distribution.tenants.arn
}

output "connection_group_id" {
  description = "ID of the CloudFront connection group tenant sites are reached through"
  value       = aws_cloudfront_connection_group.tenants.id
}

output "connection_group_arn" {
  description = "ARN of the CloudFront connection group"
  value       = aws_cloudfront_connection_group.tenants.arn
}

output "cname_target" {
  description = "What customers point their domain's CNAME at"
  value       = aws_cloudfront_connection_group.tenants.routing_endpoint
}

output "sites_bucket_name" {
  description = "Name of the tenant-sites bucket"
  value       = aws_s3_bucket.sites.id
}

output "sites_bucket_arn" {
  description = "ARN of the tenant-sites bucket"
  value       = aws_s3_bucket.sites.arn
}

output "ses_identity_arn" {
  description = "ARN of the mail.<domain> SES identity"
  value       = aws_sesv2_email_identity.mail.arn
}

output "no_reply_address" {
  description = "Sender address every tenant's emails go out from"
  value       = "noreply@${local.mail_domain}"
}
