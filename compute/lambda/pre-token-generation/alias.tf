# Stable entry point every caller invokes. This function's code ships from
# this repo (zip), so the alias simply follows each version Terraform
# publishes - no CodeDeploy traffic shifting for it.
resource "aws_lambda_alias" "live" {
  name             = "live"
  function_name    = aws_lambda_function.this.function_name
  function_version = aws_lambda_function.this.version
}
