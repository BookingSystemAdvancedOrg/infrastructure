output "api_id" {
  description = "ID of the HTTP API"
  value       = aws_apigatewayv2_api.this.id
}

output "api_endpoint" {
  description = "Default invoke URL of the HTTP API - base URL the front-end calls (e.g. https://xxxx.execute-api.eu-north-1.amazonaws.com)"
  value       = aws_apigatewayv2_stage.this.invoke_url
}

output "api_name" {
  description = "Name of the HTTP API (for alarm texts)"
  value       = aws_apigatewayv2_api.this.name
}
