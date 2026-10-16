output "onboarding_state_machine_arn" {
  description = "ARN of the tenant onboarding state machine"
  value       = aws_sfn_state_machine.onboarding.arn
}

output "domain_attach_state_machine_arn" {
  description = "ARN of the custom-domain attach state machine"
  value       = aws_sfn_state_machine.domain_attach.arn
}

output "domain_detach_state_machine_arn" {
  description = "ARN of the custom-domain detach state machine"
  value       = aws_sfn_state_machine.domain_detach.arn
}

output "offboarding_state_machine_arn" {
  description = "ARN of the tenant offboarding state machine"
  value       = aws_sfn_state_machine.offboarding.arn
}
