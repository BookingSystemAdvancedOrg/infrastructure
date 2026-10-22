# Transactional e-mail (booking, order and catering messages from the
# notification function) gets its own SES configuration set, separate from
# marketing (marketing/main.tf), so its reputation and bounces can be told
# apart. The account-level reputation alarms are in monitoring/alerts.

locals {
  transactional_config_set = "${var.env == "prod" ? "" : "${var.env}-"}transactional"
}

resource "aws_sesv2_configuration_set" "transactional" {
  configuration_set_name = local.transactional_config_set

  sending_options {
    sending_enabled = true
  }

  reputation_options {
    reputation_metrics_enabled = true
  }

  # Hard bounces only: a complaint about a confirmation must not stop the
  # guest's next booking confirmation.
  suppression_options {
    suppressed_reasons = ["BOUNCE"]
  }

  tags = {
    Environment = var.env
  }
}

# Send, bounce and complaint counts per configuration set in CloudWatch.
resource "aws_sesv2_configuration_set_event_destination" "transactional_metrics" {
  configuration_set_name = aws_sesv2_configuration_set.transactional.configuration_set_name
  event_destination_name = "transactional-metrics"

  event_destination {
    enabled              = true
    matching_event_types = ["SEND", "BOUNCE", "COMPLAINT", "REJECT"]

    cloud_watch_destination {
      dimension_configuration {
        dimension_name          = "ses:configuration-set"
        dimension_value_source  = "MESSAGE_TAG"
        default_dimension_value = local.transactional_config_set
      }
    }
  }
}

# notification sends with ConfigurationSetName: SES then also authorizes
# ses:SendEmail against the configuration set.
resource "aws_iam_role_policy" "notification_transactional_config_set" {
  name = "ses-transactional-configuration-set"
  role = module.notification_role.role_name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid      = "SendWithTransactionalConfigurationSet"
      Effect   = "Allow"
      Action   = "ses:SendEmail"
      Resource = aws_sesv2_configuration_set.transactional.arn
    }]
  })
}
