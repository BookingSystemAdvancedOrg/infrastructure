
env = "prod"

# Operators of the SaaS platform (you) - the only accounts that can create,
# suspend and offboard tenants. Separate Cognito pool, MFA required.
platform_operator_emails = [
  "lamo.kouravand@ithjalparna.se",
  "arya.eisa@ithjalparna.se",
]

dlq_replay_interval_minutes = 720 # every 12 hours - stays inside the 24h stream-record window

alert_emails = [
  "lamo.kouravand@ithjalparna.se",
  "arya.eisa@ithjalparna.se",
]

# Domain the platform owns - leave unset until decided. Setting it turns on
# tenant subdomains, customer custom domains, app./ops. hostnames and the
# SES sending domain (see docs/PLATFORM-SETUP.md, "Platform domain").
# platform_domain = "bokning.example.se"

# Public keys handed to restaurant websites by GET /site-config - not
# secrets (see docs/PLATFORM-SETUP.md).
# stripe_publishable_key = "pk_live_..."
# turnstile_site_key     = "0x..."

# VAT rates created on every new restaurant's Stripe account - set once an
# accountant has confirmed them.
# default_tax_rates = {
#   food = { display_name = "Moms", percentage = 12, inclusive = true }
# }
