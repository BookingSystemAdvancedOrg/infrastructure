
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
# turnstile_site_key     = "0x..."

# VAT rates created on every new restaurant's Stripe account - set once an
# accountant has confirmed them.
# default_tax_rates = {
#   food = { display_name = "Moms", percentage = 12, inclusive = true }
# }
