# The one custom event bus features publish to (CONTRACTS.md section 5):
# source booqy.<feature-id>, published with application shared/events.py.
# Producers get events:PutEvents on this bus with an events:source
# condition in their own module; consumers create their own rule and SQS
# DLQ in their own module. Nothing here but the bus.
locals {
  name = var.environment == "prod" ? "booqy-events" : "${var.environment}-booqy-events"
}

resource "aws_cloudwatch_event_bus" "this" {
  name = local.name

  tags = {
    Environment = var.environment
  }
}
