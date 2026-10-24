
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
# dev and prod DNS never touch. Turns on the restaurang./admin. hostnames,
# the SES sending domain mail.dev.booqy.se and (tenant_sites_enabled below)
# restaurant custom domains (see docs/PLATFORM-SETUP.md, "Platform domain").
# dev.booqy.se is delegated from the booqy.se zone in prod (NS record, also
# kept by prod.tfvars platform_subdomain_delegations), so the wildcard
# certificate validates here.
platform_domain         = "dev.booqy.se"
platform_domain_zone_id = "Z0571042RSRT4D1DDZ1L"

# Restaurant websites on each restaurant's own domain (e.g. www.arya.se),
# attached from Booqy Console: the restaurant adds one CNAME, CloudFront
# issues the certificate.
tenant_sites_enabled = true

# Dev only: every restaurant also gets <slug>.dev.booqy.se at onboarding, so
# its site works (and can be previewed) before a custom domain is attached.
# A *.dev.booqy.se CNAME to the connection group; every fixed name in the zone
# (dev., www., restaurang., restaurant., admin., mail.) has its own records,
# so the wildcard never captures them. Adds cloudfront:CreateDistributionTenant
# / GetDistributionTenant to the onboarding workflow role (owner-approved
# 2026-10-20). Whether prod should do the same is still open.
tenant_subdomains_enabled = true

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

# Subscription prices (SEK per month, excluding VAT) invoiced through Stripe
# Billing on the platform account (sandbox mode). PLACEHOLDERS: set the real
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

# Offboarded restaurants: data deleted 1 day after offboarding, checked every
# hour, so the whole flow can be tested in a day.
tenant_data_retention_days = 1
tenant_purge_schedule      = "rate(1 hour)"

# A restaurant that always exists in dev, by host: the pipelines' smoke tests
# and the 5-minute uptime check (monitoring/alerts) call
# GET /site-config?host=<this> and load https://<this>/, expecting 200.
# test-restaurang-2 (customer-front-end's VITE_DEV_TENANT_SLUG_DEV) exists
# but was onboarded before <slug>.dev.booqy.se sites were on, so its host
# has no distribution tenant yet (TLS fails). Until "re-run setup" has been
# done for it in Booqy Console the checks run in the fallback mode: the
# customer site's own distribution and a 404 for an unknown host.
# smoke_test_host = "test-restaurang-2.dev.booqy.se"

# Guest data retention (privacy-variables.tf). The job only logs counts per
# data type until this is set to false, after the owner has checked them.
# Periods: var.data_retention (defaults: bookings 395 days, contact details
# 24 months, cancelled quotes 12 months, receipts 7 years, suppression 36 months).
data_retention_dry_run = true

# DMARC aggregate reports (privacy-variables.tf). The mailbox must exist.
dmarc_report_address = "dmarc@booqy.se"
