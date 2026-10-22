# The API's base URL from the API itself, not the stage: the stage depends on
# the printer routes (throttles), whose Lambda takes this URL in its settings.
output "api_base_url" {
  description = "Base URL of the HTTP API ($default stage), e.g. https://xxxx.execute-api.eu-north-1.amazonaws.com"
  value       = aws_apigatewayv2_api.this.api_endpoint
}
