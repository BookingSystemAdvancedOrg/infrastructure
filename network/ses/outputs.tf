output "identity_arn" {
  description = "ARN of the SES identity mail is sent through (the sender's domain)"
  value       = aws_sesv2_email_identity.sender_domain.arn
  sensitive   = true
}

output "sender_domain" {
  description = "Domain of the no-reply sender address - the SES identity"
  value       = local.sender_domain
}

output "dkim_records" {
  description = "The three DKIM CNAME records to publish at the sender domain's DNS provider"
  value = [
    for token in aws_sesv2_email_identity.sender_domain.dkim_signing_attributes[0].tokens : {
      type  = "CNAME"
      name  = "${token}._domainkey.${local.sender_domain}"
      value = "${token}.dkim.amazonses.com"
    }
  ]
}
