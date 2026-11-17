# Bot check for the restaurant websites (owner 2026-11-17: AWS WAF, replacing
# the Cloudflare widget). One web ACL (CLOUDFRONT scope, so us-east-1: the
# module is called with providers = { aws = aws.us_east_1 }) on the
# distributions that serve the sites: the multi-tenant distribution
# (network/platform-domain) and, in dev, the test-sites sandbox.
#
# How it works: the sites send their form posts (booking, order, catering
# request, gift card, waiting list, ticket, newsletter) to /api/* on their
# own domain. That path is proxied to the API with two origin headers:
# x-booqy-edge (viewer IP trusted, as on the admin app) and x-booqy-waf
# (this ACL's rules ran). The guest site loads the ACL's JavaScript
# integration (application_integration_url + /challenge.js), which proves a
# real browser and keeps a short-lived aws-waf-token cookie on the site's
# own domain. Same domain as the request, so no token domain list is
# needed, and every restaurant domain (own domain, <slug>.booqy.se, test
# hosts) is covered without any per-restaurant setup.
#
#   ip-reputation   AWS managed list of known bad IPs (bots, scanners): block
#   api-rate-limit  more than var.api_rate_limit requests to /api/* per IP in
#                   5 minutes: 429
#   bot-control     AWS Bot Control (targeted) on /api/*, counting only (needed for the
#                   JavaScript integration URL, see the rule)
#   api-challenge   a write (anything but GET, HEAD, OPTIONS) to /api/*
#                   without a valid token: silent challenge (HTTP 202,
#                   x-amzn-waf-action: challenge); the site gets a token and
#                   sends the post again
#
# Page loads (everything outside /api/*) are never challenged.
#
# Cost (us-east-1 list price): $5 per month for the ACL, $1 per rule per
# month, $0.60 per million requests, $10 per month for Bot Control plus its
# per-request fee for the targeted level (only /api/ requests, the form
# posts), plus a fee per challenge served (only requests without a valid
# token, in practice bots). About $20 per month per environment at today's
# volume.

terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
  }
}

locals {
  name = "${var.environment}-tenant-sites"
}

resource "aws_wafv2_web_acl" "sites" {
  name        = local.name
  description = "Restaurant websites: bot check on api writes, rate limit, IP reputation"
  scope       = "CLOUDFRONT"

  default_action {
    allow {}
  }

  # A token stays valid for 5 minutes after the challenge; the integration
  # script renews it in the background while the page is open.
  challenge_config {
    immunity_time_property {
      immunity_time = 300
    }
  }

  custom_response_body {
    key          = "rate_limited"
    content_type = "APPLICATION_JSON"
    content      = jsonencode({ error = "rate_limited", message = "För många försök. Vänta några minuter och försök igen." })
  }

  rule {
    name     = "ip-reputation"
    priority = 0

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        vendor_name = "AWS"
        name        = "AWSManagedRulesAmazonIpReputationList"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${local.name}-ip-reputation"
      sampled_requests_enabled   = true
    }
  }

  # AWS Bot Control (targeted level), counting only: it never blocks here
  # (the challenge rule is the check), but a web ACL only gets a JavaScript
  # integration URL (application_integration_url, the sites' challenge.js)
  # with a rule group that uses the SDK's tokens; the common level does not
  # (checked in dev 2026-11-17). Scoped to /api/* so page loads are not
  # inspected: Bot Control is billed per request inspected, and only the
  # sites' form posts go to /api/*.
  rule {
    name     = "bot-control"
    priority = 3

    override_action {
      count {}
    }

    statement {
      managed_rule_group_statement {
        vendor_name = "AWS"
        name        = "AWSManagedRulesBotControlRuleSet"

        managed_rule_group_configs {
          aws_managed_rules_bot_control_rule_set {
            inspection_level = "TARGETED"
          }
        }

        scope_down_statement {
          byte_match_statement {
            search_string         = "/api/"
            positional_constraint = "STARTS_WITH"
            field_to_match {
              uri_path {}
            }
            text_transformation {
              priority = 0
              type     = "NONE"
            }
          }
        }
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${local.name}-bot-control"
      sampled_requests_enabled   = true
    }
  }

  rule {
    name     = "api-rate-limit"
    priority = 1

    action {
      block {
        custom_response {
          response_code            = 429
          custom_response_body_key = "rate_limited"
        }
      }
    }

    statement {
      rate_based_statement {
        limit                 = var.api_rate_limit
        evaluation_window_sec = 300
        aggregate_key_type    = "IP"

        scope_down_statement {
          byte_match_statement {
            search_string         = "/api/"
            positional_constraint = "STARTS_WITH"
            field_to_match {
              uri_path {}
            }
            text_transformation {
              priority = 0
              type     = "NONE"
            }
          }
        }
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${local.name}-api-rate-limit"
      sampled_requests_enabled   = true
    }
  }

  rule {
    name     = "api-challenge"
    priority = 2

    action {
      challenge {}
    }

    statement {
      and_statement {
        statement {
          byte_match_statement {
            search_string         = "/api/"
            positional_constraint = "STARTS_WITH"
            field_to_match {
              uri_path {}
            }
            text_transformation {
              priority = 0
              type     = "NONE"
            }
          }
        }

        statement {
          not_statement {
            statement {
              or_statement {
                dynamic "statement" {
                  for_each = ["GET", "HEAD", "OPTIONS"]
                  content {
                    byte_match_statement {
                      search_string         = statement.value
                      positional_constraint = "EXACTLY"
                      field_to_match {
                        method {}
                      }
                      text_transformation {
                        priority = 0
                        type     = "NONE"
                      }
                    }
                  }
                }
              }
            }
          }
        }
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${local.name}-api-challenge"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = local.name
    sampled_requests_enabled   = true
  }

  tags = {
    Environment = var.environment
  }
}
