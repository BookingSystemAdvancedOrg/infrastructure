# Role that EventBridge Scheduler itself assumes when the recurring
# dlq-replay schedule fires, so it can invoke the replay Lambda.
#
# This is NOT a Lambda execution role - it's never assumed by a Lambda, so
# it has no CloudWatch Logs permission of its own. Its only job is letting
# the scheduler.amazonaws.com service call this one function.

resource "aws_iam_role" "this" {
  name = var.environment == "prod" ? "scheduler-invoke-dlq-replay-role" : "${var.environment}-scheduler-invoke-dlq-replay-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { Service = "scheduler.amazonaws.com" }
        Action    = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Environment = var.environment
  }
}

resource "aws_iam_role_policy" "invoke_dlq_replay" {
  name = "invoke-dlq-replay-function"
  role = aws_iam_role.this.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "InvokeDlqReplayFunction"
        Effect   = "Allow"
        Action   = "lambda:InvokeFunction"
        Resource = "${var.dlq_replay_lambda_arn}"
      }
    ]
  })
}
