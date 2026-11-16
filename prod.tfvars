
env = "prod"

# Operators of the SaaS platform (you) - the only accounts that can create,
# suspend and offboard tenants. Separate Cognito pool, MFA required.
platform_operator_emails = [
  "lamo.kouravand@ithjalparna.se",
  "arya.eisa@ithjalparna.se",
]

# Owners (platform_owner group): may change any operator's e-mail in Booqy
# Console. Cognito usernames (the sub), not e-mails; find yours with
# aws cognito-idp admin-get-user --user-pool-id <operator pool> --username <your e-mail>
platform_owner_usernames = ["600c29ac-1081-7019-1813-a8cb80d44eec"]

dlq_replay_interval_minutes = 15 # every 15 minutes - delayed emails and kitchen tickets stay short, well inside the 24h stream-record window

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

# Both Cognito pools email invitations and password resets through SES from
# mail.booqy.se (verified; SES production access granted), and the reset
# email carries a link. Cognito's built-in sender (verificationemail.com,
# 50 a day) was not reaching staff inboxes, e.g. on ithjalparna.se.
cognito_invites_via_ses = true

# Restaurant websites on each restaurant's own domain (e.g. www.arya.se),
# attached from Booqy Console: the restaurant adds one CNAME, CloudFront
# issues the certificate.
tenant_sites_enabled = true

# Every restaurant also gets <slug>.booqy.se at onboarding, so its site is
# live before (and keeps working after) its own domain is attached (owner's
# decision 2026-10-28; was off). A *.booqy.se CNAME to the connection group:
# every fixed name in the zone (apex, www., restaurang., restaurant.,
# admin., mail., dev.) has its own records, and those names are reserved
# slugs, so the wildcard never captures them. Adds the same
# cloudfront:CreateDistributionTenant / GetDistributionTenant statement to
# the onboarding role that dev has had since 2026-10-20 (owner-approved).
tenant_subdomains_enabled = true

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
  # Test sites (dev account, test-sites.tf): test.booqy.se and
  # test-dev.booqy.se. Uncomment with the 4 name servers each from the dev
  # apply's outputs test_sites_main_name_servers / test_sites_dev_name_servers
  # (rollout step 2), then the owner merges to main; or add the two NS
  # records by hand in the booqy.se zone first (adopted, allow_overwrite).
  test = [
    "ns-975.awsdns-57.net",
    "ns-1639.awsdns-12.co.uk",
    "ns-1530.awsdns-63.org",
    "ns-197.awsdns-24.com",
  ]
  test-dev = [
    "ns-195.awsdns-24.com",
    "ns-944.awsdns-54.net",
    "ns-1972.awsdns-54.co.uk",
    "ns-1386.awsdns-45.org",
  ]
}

# Public keys handed to restaurant websites by GET /site-config - not
# secrets (see docs/PLATFORM-SETUP.md).
# stripe_publishable_key = "pk_live_..."
# turnstile_site_key     = "0x..."

# Monthly prices (SEK, excluding VAT), invoiced in advance on the 1st for
# that calendar month (the first month pro rata from the start day)
# through Stripe on the platform account (live mode). Growth = 3 x Starter
# with 30 % off (3950 x 3 x 0.7). A changed price applies to customers on
# the plan's price from the next month (the daily task records
# it); a customer's own price in Booqy Console is not affected.
plans = {
  starter = {
    name          = "Starter"
    max_locations = 1
    features = {
      reservations = true, ordering = true, catering = false, marketing = false,
      metaAds      = false, siteBuilder = false, guestCrm = false, googleBusiness = false, giftCards = false,
      waitlist     = false, socialPosting = false, personalliggare = false, accountingSync = false, dishMargin = false,
      events       = false, phoneAgent = false,
    }
    price_sek = 3950
    limits    = { siteBuilderAiEditsPerMonth = 0, phoneAgentMinutesPerMonth = 0 }
  }
  growth = {
    name          = "Growth"
    max_locations = 3
    features = {
      reservations = true, ordering = true, catering = true, marketing = true,
      metaAds      = false, siteBuilder = false, guestCrm = false, googleBusiness = false, giftCards = false,
      waitlist     = false, socialPosting = false, personalliggare = false, accountingSync = false, dishMargin = false,
      events       = false, phoneAgent = false,
    }
    price_sek = 8295
    limits    = { siteBuilderAiEditsPerMonth = 0, phoneAgentMinutesPerMonth = 0 }
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

# The prod test restaurant test-release (deployed site repo, checked
# 2026-11-16): the uptime check and the smoke tests load its site through
# the tenant-sites path and expect GET /site-config to answer 200. Never
# offboard it while this is set; unset, they load the shared customer
# build and expect a 404 for an unknown host instead.
smoke_test_host = "test-release.booqy.se"

# Guest data retention (privacy-variables.tf). The job only logs counts per
# data type until this is set to false, after the owner has checked them.
# Periods: var.data_retention (defaults: bookings 395 days, contact details
# 24 months, cancelled quotes 12 months, receipts 7 years, suppression 36 months).
data_retention_dry_run = true

# DMARC aggregate reports (privacy-variables.tf). The mailbox must exist.
dmarc_report_address = "dmarc@booqy.se"

# Restaurant websites, one private repo site-<slug> per customer (sites.tf,
# docs/CUSTOMER-SITE-RUNBOOK.md). Off until the "Booqy Sites" GitHub App's
# key is stored by hand in this secret (JSON {"app_id", "private_key"}):
# uncomment, push, and new customers get their repo at onboarding.
github_app_sites_secret_name = "booqy/prod/github-app-sites"
# Site repos live in their own org (App "Booqy Customer Sites"), apart
# from the platform repos in var.github_org.
site_github_org = "BooqyCustomers"
# Its numeric id: site-repo writes a deploy role trust only for a repo this
# org owns, by login AND id (prod never writes one for BooqyCustomersDev).
site_github_org_id = "356944191"
# Every restaurant domain is served from its own site repo (sites/<tenantId>/)
# instead of the shared customer-front-end build. On 2026-11-16 the only
# domain (test-release) had a deployed site; a new domain gets its repo at
# onboarding.
per_tenant_sites = true
# A site repo is born in the prod console, which also sets up its dev side
# through the dev account's booqy-sites-prod-link role (sites/main.tf).
site_link_dev_account_id = "877653167825"

# The account's monthly SMS spend limit (USD), alarmed at 80%. AWS raised
# this account's SMS quota to 50 USD and moved it out of the SMS sandbox
# (support case, 2026-10-27). Ask for more once usage passes half of it.
sms_monthly_spend_limit_usd = 50

# AI phone agent brain (owner 2026-11-13): Claude Haiku 5.5, as in dev. The
# clients stay simulators (the feature is off in every plan) until go-live.
phone_agent_model_id = "eu.anthropic.claude-haiku-5-5"

# Fråga Booqy / Ask Booqy (owner 2026-11-16): on in prod with Claude Haiku 5.5
# on Bedrock through the EU inference profile, as in dev. Cost caps
# (help_assistant_monthly_answers) keep it near USD 6 a month; past a cap,
# answers come from the help texts alone. Off at runtime without a deploy:
# PLATFORM#HELP_ASSISTANT/SETTINGS {enabled: false} on the tenant table.
help_assistant_enabled        = true
help_assistant_bedrock_client = "real"
help_assistant_model_id       = "eu.anthropic.claude-haiku-5-5"

# The seller on every invoice (not secret): Booqy is a product of IT Hjälparna
# Nordic AB, so the AB is the legal seller; the invoice lines say "Booqy".
# Registered for VAT and F-skatt, säte Finspång (Bolagsverket and Skatteverket
# via allabolag.se, 2026-11-16). Without name, address, org_number and
# vat_number prod invoices nothing (check billing_seller_prod in config.tf).
billing_seller = {
  name       = "IT Hjälparna Nordic AB"
  address    = "Vallmovägen 9, 612 46 Finspång"
  org_number = "559594-8810"
  vat_number = "SE559594881001"
  seat       = "Finspång"
  f_skatt    = true
}

# Google Business Profile (feature D): simulator until the owner releases it
# (prod refuses the simulator at runtime, so the feature stays off). "real"
# here also needs google_business_prod_released = true, or the plan fails.
google_business_client = "simulator"
