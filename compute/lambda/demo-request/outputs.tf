output "function_name" {
  description = "Name of the demo-request Lambda"
  value       = aws_lambda_function.this.function_name
}

output "alias_name" {
  description = "Name of the alias the function URL points at"
  value       = aws_lambda_alias.live.name
}

output "function_url_domain" {
  description = "Host name of the function URL (no scheme, no slash) - the landing distribution's /api/* origin"
  value       = trimsuffix(trimprefix(aws_lambda_function_url.this.function_url, "https://"), "/")
}
