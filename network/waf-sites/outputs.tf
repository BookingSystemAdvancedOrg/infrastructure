output "web_acl_arn" {
  description = "ARN of the restaurant websites' web ACL (CLOUDFRONT scope)"
  value       = aws_wafv2_web_acl.sites.arn
}

output "application_integration_url" {
  description = "Base URL of the web ACL's JavaScript integration; the sites load <url>challenge.js (handed out by GET /site-config)"
  value       = aws_wafv2_web_acl.sites.application_integration_url
}
