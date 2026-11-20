output "phone_number" {
  description = "The test line's number (E.164): call it to talk to the agent"
  value       = aws_connect_phone_number.this.phone_number
}

# The dev A2A test (a2a-dev-test/) builds on this instance and falls back to this flow.
output "instance_id" {
  value = aws_connect_instance.this.id
}

output "instance_arn" {
  value = aws_connect_instance.this.arn
}

output "contact_flow_arn" {
  description = "The Stage 1 flow"
  value       = aws_connect_contact_flow.this.arn
}
