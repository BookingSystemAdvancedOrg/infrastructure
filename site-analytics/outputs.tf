output "function_url_domain" {
  description = "Host name of the function URL (no scheme, no slash): the landing distribution's /api/collect origin"
  value       = trimsuffix(trimprefix(aws_lambda_function_url.this.function_url, "https://"), "/")
}

output "table_name" {
  description = "The site-analytics table (raw hits, daily aggregates) the Website page reads"
  value       = aws_dynamodb_table.analytics.name
}
