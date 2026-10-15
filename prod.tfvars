
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

# Domain the platform owns. Turns on tenant subdomains (<slug>.booqy.se),
# customer custom domains, app./ops. hostnames and the SES sending domain
# mail.booqy.se (see docs/PLATFORM-SETUP.md, "Platform domain").
# The zone is the one Route 53 created when booqy.se was registered in this
# account - adopted, so the domain's name servers never change.
platform_domain         = "booqy.se"
platform_domain_zone_id = "Z04764661GIIKO8677SYH"

# The domain serves only app. (restaurant admin), ops. (Booqy Console) and
# mail. (SES) - no restaurant websites on <slug>.<domain> or customer
# domains (no wildcard record, no multi-tenant distribution).
tenant_sites_enabled = false

# dev.booqy.se is answered by the dev account's zone (Z0571042RSRT4D1DDZ1L).
# The NS record was created by hand first so dev could go live before prod;
# Terraform adopts it (allow_overwrite).
platform_subdomain_delegations = {
  dev = [
    "ns-1903.awsdns-45.co.uk",
    "ns-1430.awsdns-50.org",
    "ns-45.awsdns-05.com",
    "ns-981.awsdns-58.net",
  ]
}

# Public keys handed to restaurant websites by GET /site-config - not
# secrets (see docs/PLATFORM-SETUP.md).
# stripe_publishable_key = "pk_live_..."
# turnstile_site_key     = "0x..."

# VAT rates created on every new restaurant's Stripe account - set once an
# accountant has confirmed them.
# default_tax_rates = {
#   food = { display_name = "Moms", percentage = 12, inclusive = true }
# }
