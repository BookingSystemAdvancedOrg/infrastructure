output "zone_id" {
  description = "Route 53 hosted zone ID of the platform domain"
  value       = aws_route53_zone.platform.zone_id
}

output "name_servers" {
  description = "Name servers to delegate the platform domain to (NS records at the registrar / parent zone)"
  value       = aws_route53_zone.platform.name_servers
}

output "certificate_arn" {
  description = "ARN of the validated *.<domain> certificate (us-east-1) for the restaurang./admin. aliases"
  value       = aws_acm_certificate_validation.wildcard.certificate_arn
}

output "multitenant_distribution_id" {
  description = "ID of the tenant-sites multi-tenant distribution"
  value       = one(aws_cloudfront_multitenant_distribution.tenant_sites[*].id)
}

output "multitenant_distribution_arn" {
  description = "ARN of the tenant-sites multi-tenant distribution"
  value       = one(aws_cloudfront_multitenant_distribution.tenant_sites[*].arn)
}

output "connection_group_id" {
  description = "ID of the CloudFront connection group tenant sites are reached through"
  value       = one(aws_cloudfront_connection_group.tenant_sites[*].id)
}

output "connection_group_arn" {
  description = "ARN of the CloudFront connection group"
  value       = one(aws_cloudfront_connection_group.tenant_sites[*].arn)
}

output "cname_target" {
  description = "What customers point their domain's CNAME at"
  value       = one(aws_cloudfront_connection_group.tenant_sites[*].routing_endpoint)
}

output "ses_identity_arn" {
  description = "ARN of the mail.<domain> SES identity"
  value       = aws_sesv2_email_identity.mail.arn
}

output "no_reply_address" {
  description = "Sender address every tenant's emails go out from"
  value       = "noreply@${local.mail_domain}"
}

output "landing_bucket_name" {
  description = "Bucket the public page on <domain> is served from (booqy-website deploys here)"
  value       = aws_s3_bucket.landing.id
}

output "landing_bucket_arn" {
  description = "ARN of the public page bucket"
  value       = aws_s3_bucket.landing.arn
}

output "landing_distribution_id" {
  description = "CloudFront distribution serving <domain> and www.<domain> (booqy-website invalidates it after deploying)"
  value       = aws_cloudfront_distribution.landing.id
}

output "landing_distribution_arn" {
  description = "ARN of the public page distribution"
  value       = aws_cloudfront_distribution.landing.arn
}
