# Secrets for table reservations (Secrets Manager, not Lambda environment
# variables - see security/secrets/catering for why).
#
# link-signing-key: HMAC-SHA256 key behind the guest's manage link
#   /bokning/<locationId>/<reservationId>#<token>,
#   token = HMAC(key, "reservation-manage|v1|<tenant>|<location>|<reservation>|<linkVersion>")
# (application shared/manage_link.py). The token is never stored: the
# create function returns it once, the notification function rebuilds it
# for confirmation/reminder messages, and the guest routes verify it.
# PLATFORM-level (one per environment): the message pins tenant and
# location. Bumping secret_string_wo_version rotates the key - every link
# already sent stops working.

locals {
  prefix                  = var.environment == "prod" ? "" : "${var.environment}-"
  recovery_window_in_days = var.environment == "prod" ? 30 : 7
}

resource "aws_secretsmanager_secret" "link_signing_key" {
  name                    = "${local.prefix}reservations/link-signing-key"
  description             = "HMAC key for guests' reservation manage links"
  recovery_window_in_days = local.recovery_window_in_days

  tags = {
    Environment = var.environment
  }
}

ephemeral "aws_secretsmanager_random_password" "link_signing_key" {
  password_length     = 64
  exclude_punctuation = true
}

resource "aws_secretsmanager_secret_version" "link_signing_key" {
  secret_id                = aws_secretsmanager_secret.link_signing_key.id
  secret_string_wo         = ephemeral.aws_secretsmanager_random_password.link_signing_key.random_password
  secret_string_wo_version = 1 # bump to rotate - every manage link already sent stops working
}

# Read access for exactly the functions that build or verify links.
resource "aws_iam_policy" "read_link_signing_key" {
  name        = "${local.prefix}reservation-link-signing-key-read"
  description = "Read the reservation manage-link signing key"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ReadReservationLinkSigningKey"
        Effect   = "Allow"
        Action   = "secretsmanager:GetSecretValue"
        Resource = aws_secretsmanager_secret.link_signing_key.arn
      }
    ]
  })

  tags = {
    Environment = var.environment
  }
}

resource "aws_iam_role_policy_attachment" "read_link_signing_key" {
  for_each   = var.reader_role_names
  role       = each.value
  policy_arn = aws_iam_policy.read_link_signing_key.arn
}
