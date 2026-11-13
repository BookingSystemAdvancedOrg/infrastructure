output "phone_number" {
  description = "The test line's number (E.164): call it to talk to the agent"
  value       = aws_connect_phone_number.this.phone_number
}
