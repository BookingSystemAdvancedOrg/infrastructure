# Stable entry point every caller invokes (API Gateway, streams, Scheduler,
# other Lambdas). New code goes live by publishing a version and shifting
# this alias with CodeDeploy (orchestration/lambda-releases) - so Terraform only
# creates the alias and never moves it afterwards, or every apply would
# undo (or race) a release.
resource "aws_lambda_alias" "live" {
  name             = "live"
  function_name    = aws_lambda_function.this.function_name
  function_version = aws_lambda_function.this.version

  lifecycle {
    ignore_changes = [function_version, routing_config]
  }
}
