# SES no-reply identity. Used by NotificationFn to email customers a Stripe
# Payment Link when a charge fails (cancelled_charge_failed /
# no_show_charge_failed). Not used for staff invites - those go through
# Cognito's own mailer.
#
# MANUAL STEP: after first deploy, verify this address (click the link SES
# emails to it), then request SES Production Access in the console -
# sandbox mode blocks sending to real customer addresses until approved.
resource "aws_ses_email_identity" "no_reply" {
  email = var.no_reply_email_address
}
