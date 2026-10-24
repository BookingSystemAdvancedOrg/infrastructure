variable "environment" {
  description = "The environment to deploy to (dev or prod)"
  type        = string
  sensitive   = false
}

variable "region" {
  description = "AWS region (for the log group ARN)"
  type        = string
}

variable "site" {
  description = "The platform domain the statistics are for (booqy.se / dev.booqy.se): part of the visitor hash, and not counted as a referrer"
  type        = string
}

variable "landing_distribution_arn" {
  description = "The landing CloudFront distribution (network/platform-domain), the only caller of the function URL"
  type        = string
}

variable "console_role_name" {
  description = "Execution role of platform-tenants (Booqy Console's API), given read access for the Website page"
  type        = string
}

variable "alert_topic_arn" {
  description = "SNS topic the error alarm notifies (monitoring/alerts)"
  type        = string
}

variable "reserved_concurrency" {
  description = "Most hits handled at once; caps what a flood of fake hits can cost"
  type        = number
  default     = 5
}

variable "rollup_schedule" {
  description = "How often today's and yesterday's aggregates are recomputed"
  type        = string
  default     = "rate(15 minutes)"
}
