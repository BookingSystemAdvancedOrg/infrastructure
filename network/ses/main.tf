# SES sender identity for every platform email (guest confirmations,
# reminders, restaurant alerts, payment links) - From: "<restaurant>"
# <var.no_reply_email_address>, Reply-To: the restaurant.
#
# The DOMAIN of that address is the identity, not the address itself: SES
# then sends from noreply@<domain> without any mailbox existing, and every
# message is DKIM-signed with the domain (needed to land in the inbox, not
# spam, and to pass DMARC).
#
# MANUAL STEP (once per AWS account - dev and prod each get their own 3
# records): publish the three DKIM CNAMEs from the `ses_dkim_records`
# output at the domain's DNS provider. SES verifies within minutes to an
# hour. Then request SES production access in prod - sandbox mode only
# delivers to verified addresses.

locals {
  sender_domain = lower(element(split("@", var.no_reply_email_address), 1))
}

resource "aws_sesv2_email_identity" "sender_domain" {
  email_identity = local.sender_domain

  dkim_signing_attributes {
    next_signing_key_length = "RSA_2048_BIT"
  }
}
