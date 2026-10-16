output "app_name" {
  description = "CodeDeploy application every Lambda release goes through"
  value       = aws_codedeploy_app.lambda.name
}

output "deployment_group_names" {
  description = "Map of function name to its CodeDeploy deployment group name"
  value       = { for k, g in aws_codedeploy_deployment_group.this : k => g.deployment_group_name }
}

output "deployment_group_arns" {
  description = "Map of function name to its CodeDeploy deployment group ARN - for scoping deploy-role permissions"
  value       = { for k, g in aws_codedeploy_deployment_group.this : k => g.arn }
}

output "app_arn" {
  description = "ARN of the CodeDeploy application - for scoping deploy-role permissions"
  value       = aws_codedeploy_app.lambda.arn
}
