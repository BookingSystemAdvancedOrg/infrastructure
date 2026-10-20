# CloudFront publishes its metrics in us-east-1 only, and a CloudWatch alarm
# can only notify an SNS topic in its own region - so the CloudFront alarms
# (front-door.tf) and a second alerts topic live in us-east-1 and need the
# aliased provider. Everything else in this module stays in the primary
# region. archive zips the uptime-check Lambda (uptime.tf).
terraform {
  required_providers {
    aws = {
      source                = "hashicorp/aws"
      configuration_aliases = [aws.us_east_1]
    }
    archive = {
      source = "hashicorp/archive"
    }
  }
}
