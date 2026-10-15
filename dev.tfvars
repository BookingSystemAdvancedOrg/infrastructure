
env = "dev"

# Operators of the SaaS platform (you) - the only accounts that can create,
# suspend and offboard tenants. Separate Cognito pool, MFA required.
platform_operator_emails = [
  "lamo.kouravand@ithjalparna.se",
  "arya.eisa@ithjalparna.se",
]

dlq_replay_interval_minutes = 6 # every 6 minutes - fast feedback while testing

alert_emails = [
  "lamo.kouravand@ithjalparna.se",
  "arya.eisa@ithjalparna.se",
]

# Domain the platform owns. Dev runs on dev.booqy.se: its own hosted zone in
# THIS account (created by hand, delegated from the booqy.se zone in prod), so
# dev and prod DNS never touch. Turns on tenant subdomains (<slug>.dev.booqy.se),
# customer custom domains, app./ops. hostnames and the SES sending domain
# mail.dev.booqy.se (see docs/PLATFORM-SETUP.md, "Platform domain").
# Switched on once booqy.se is registered and dev.booqy.se is delegated
# from prod (the wildcard certificate validates through that delegation):
# platform_domain         = "dev.booqy.se"
# platform_domain_zone_id = "Z0571042RSRT4D1DDZ1L"

# Public keys handed to restaurant websites by GET /site-config - not
# secrets (see docs/PLATFORM-SETUP.md).
stripe_publishable_key = "pk_test_51U4OsHHhsMraauJUMyW7ID1lQq1jsS3Pdtzqu04WDgEnJW8VQIvGktIUNMPo8cZNgIRYPafALaLKQxLfckdiXOKX00LbiD1Obc"
# Cloudflare's TEST site key (always passes; its secret counterpart is
# written by security/secrets/catering outside prod). Online bookings in dev
# therefore run the real bot check with a "testing only" widget.
turnstile_site_key = "1x00000000000000000000AA"

# The account's monthly SMS spend limit (USD), alarmed at 80% - check the
# current value first: aws sns get-sms-attributes --region eu-north-1
sms_monthly_spend_limit_usd = 1

# Both Cognito pools email through SES instead of Cognito's built-in sender -
# needed for the "forgot password" LINK emails (Cognito only sends a custom
# email through SES). Off until booqy.se is live: set platform_domain above,
# wait until the mail.dev.booqy.se identity is verified
# (aws sesv2 get-email-identity --email-identity mail.dev.booqy.se --region eu-north-1 --query VerifiedForSendingStatus),
# then set this to true. Until then the reset email shows a 6-digit code,
# which both apps accept. While this account's SES is in the sandbox,
# Cognito's emails then only reach verified addresses/domains.
cognito_invites_via_ses = false
# Until booqy.se is verified in SES, emails are saved to a private S3
# outbox instead of sent - read them in Booqy Console under "Mail outbox".
# Switch off (false) once mail.dev.booqy.se is verified to send for real.
mail_outbox = true

# VAT rates created on every new restaurant's Stripe account - set once an
# accountant has confirmed them.
# default_tax_rates = {
#   food = { display_name = "Moms", percentage = 12, inclusive = true }
# }
