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

# Built from the name, not the resource: the platform-tenants Lambda that
# starts this workflow is also the one it invokes, so a resource reference
# here would be a dependency cycle.
output "domain_provision_state_machine_arn" {
  description = "ARN of the domain-provision state machine (bought / connected domains)"
  value       = local.state_machine_arns.domain_provision
}
