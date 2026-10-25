
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

# Domain the platform owns. Turns on the restaurang./admin. hostnames,
# the SES sending domain mail.booqy.se and (tenant_sites_enabled below)
# restaurant custom domains (see docs/PLATFORM-SETUP.md, "Platform domain").
# The zone is the one Route 53 created when booqy.se was registered in this
# account - adopted, so the domain's name servers never change.
platform_domain         = "booqy.se"
platform_domain_zone_id = "Z04764661GIIKO8677SYH"

# Restaurant websites on each restaurant's own domain (e.g. www.arya.se),
# attached from Booqy Console: the restaurant adds one CNAME, CloudFront
# issues the certificate. No <slug>.<domain> sites - booqy.se itself never
# hosts a restaurant site (tenant_subdomains_enabled stays false).
tenant_sites_enabled = true

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

# Subscription prices (SEK per month, excluding VAT) invoiced through Stripe
# Billing on the platform account (live mode). PLACEHOLDERS: set the real
# prices before the first subscription is started. Changing a price creates
# a new Stripe price; a customer moves to it the next time their plan is
# saved in Booqy Console.
plans = {
  starter = {
    name          = "Starter"
    max_locations = 1
    features      = { reservations = true, ordering = true, catering = false, terminal = true, marketing = false, kassa = false }
    price_sek     = 990
  }
  growth = {
    name          = "Growth"
    max_locations = 3
    features      = { reservations = true, ordering = true, catering = true, terminal = true, marketing = true, kassa = false }
    price_sek     = 1990
  }
}

# VAT rates created on every new restaurant's Stripe account - set once an
# accountant has confirmed them.
# default_tax_rates = {
#   food = { display_name = "Moms", percentage = 12, inclusive = true }
# }

# Offboarded restaurants: data deleted 90 days after offboarding, checked
# nightly at 02:00 UTC.
tenant_data_retention_days = 90
tenant_purge_schedule      = "cron(0 2 * * ? *)"

# No permanent test restaurant in production yet: the smoke tests and the
# uptime check load the customer site's own distribution and expect
# GET /site-config to answer 404 for an unknown host (which still proves
# API Gateway -> Lambda -> DynamoDB). Set this to a restaurant host that
# will always exist (e.g. a demo restaurant on its own domain) to check a
# real 200 instead.
# smoke_test_host = "demo.booqy.se"

# Guest data retention (privacy-variables.tf). The job only logs counts per
# data type until this is set to false, after the owner has checked them.
# Periods: var.data_retention (defaults: bookings 395 days, contact details
# 24 months, cancelled quotes 12 months, receipts 7 years, suppression 36 months).
data_retention_dry_run = true

# DMARC aggregate reports (privacy-variables.tf). The mailbox must exist.
dmarc_report_address = "dmarc@booqy.se"
