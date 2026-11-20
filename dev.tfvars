
env = "dev"

# Operators of the SaaS platform (you) - the only accounts that can create,
# suspend and offboard tenants. Separate Cognito pool, MFA required.
platform_operator_emails = [
  "lamo.kouravand@ithjalparna.se",
  "arya.eisa@ithjalparna.se",
]

# Owners (platform_owner group): may change any operator's e-mail in Booqy
# Console. Cognito usernames (the sub), not e-mails; find yours with
# aws cognito-idp admin-get-user --user-pool-id <operator pool> --username <your e-mail>
platform_owner_usernames = ["d03cd9ec-20d1-7022-a783-0553c14b596f"]

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
# 2026-10-20). Prod does the same (<slug>.booqy.se) since 2026-10-28.
tenant_subdomains_enabled = true

# Public keys handed to restaurant websites by GET /site-config - not
# secrets (see docs/PLATFORM-SETUP.md).
stripe_publishable_key = "pk_test_51U4OsHHhsMraauJUMyW7ID1lQq1jsS3Pdtzqu04WDgEnJW8VQIvGktIUNMPo8cZNgIRYPafALaLKQxLfckdiXOKX00LbiD1Obc"

# Bot check on the restaurant sites' form posts (AWS WAF, network/waf-sites).
# The WAF runs on every site's /api/* already; this makes the API refuse
# guest form posts that did not come through it. Off in dev: test-pizza
# still runs site-kit 0.1.0, and the E2E suites post guest forms straight to
# the dev API from a local site. Turn on once both use /api (the
# "not_through_waf" warnings in the guest Lambdas' logs then stop).
bot_check_enforced = false

# The account's monthly SMS spend limit (USD), alarmed at 80% - check the
# current value first: aws sns get-sms-attributes --region eu-north-1
# AWS raised this account's SMS quota to 50 USD (support case, 2026-10-25).
sms_monthly_spend_limit_usd = 50

# SMS delivery status in CloudWatch (sns/eu-north-1/<account>/
# DirectPublishToPhoneNumber and .../Failure, 14 days) and an alert e-mail
# for every SMS that isn't delivered. Dev logs every delivered SMS too.
# Off until the deploy role dev-infra-oidc-role may pass
# dev-sns-sms-delivery-logs to SNS (iam:PassRole, iam:PassedToService
# sns.amazonaws.com) - SetSMSAttributes fails with 403 without it.
sms_delivery_logging               = false
sms_delivery_success_sampling_rate = 100

# Both Cognito pools email through SES instead of Cognito's built-in sender -
# needed for the "forgot password" LINK emails (Cognito only sends a custom
# email through SES). Off until booqy.se is live: set platform_domain above,
# wait until the mail.dev.booqy.se identity is verified
# (aws sesv2 get-email-identity --email-identity mail.dev.booqy.se --region eu-north-1 --query VerifiedForSendingStatus),
# then set this to true. Until then the reset email shows a 6-digit code,
# which both apps accept. While this account's SES is in the sandbox,
# Cognito's emails then only reach verified addresses/domains.
cognito_invites_via_ses = false
# Emails go out through SES for real (mail.dev.booqy.se verified). This
# account's SES is still in the sandbox, so they only reach addresses
# verified in SES; mail to any other address is rejected. true = save
# emails to a private S3 outbox instead (Booqy Console, "Mail outbox").
mail_outbox = false

# Monthly prices (SEK, excluding VAT), invoiced in advance on the 1st
# through Stripe on the platform account (sandbox mode in dev). Growth = 3 x Starter
# with 30 % off (3950 x 3 x 0.7). A changed price applies to customers on
# the plan's price from the next month (the daily task records
# it); a customer's own price in Booqy Console is not affected.
plans = {
  starter = {
    name          = "Starter"
    max_locations = 1
    features = {
      reservations = true, ordering = true, catering = false, marketing = false,
      metaAds      = false, guestCrm = false, googleBusiness = false, giftCards = false,
      waitlist     = false, socialPosting = false, personalliggare = false, accountingSync = false, dishMargin = false,
      events       = false, phoneAgent = false,
    }
    price_sek = 3950
    limits    = { phoneAgentMinutesPerMonth = 0 }
  }
  growth = {
    name          = "Growth"
    max_locations = 3
    features = {
      reservations = true, ordering = true, catering = true, marketing = true,
      metaAds      = false, guestCrm = false, googleBusiness = false, giftCards = false,
      waitlist     = false, socialPosting = false, personalliggare = false, accountingSync = false, dishMargin = false,
      events       = false, phoneAgent = false,
    }
    price_sek = 8295
    limits    = { phoneAgentMinutesPerMonth = 0 }
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

# Restaurant websites, one public repo site-<slug> per customer (sites.tf,
# docs/CUSTOMER-SITE-RUNBOOK.md). Key isolation (owner 2026-11-15): this
# secret holds ONLY the "Booqy Test Sites" App key (App 5770798, org
# BooqyCustomersDev), JSON {"app_id", "private_key"}. Dev never holds the
# "Booqy Customer Sites" key.
github_app_sites_secret_name = "booqy/dev/github-app-sites"
# Real customers' repos are in BooqyCustomers. Dev makes NO GitHub call for
# them: prod's site-repo writes everything there (DEV_* variables included)
# and asks dev, through the booqy-sites-prod-link role, only for the dev
# deploy role, naming the repo. Dev writes that trust only for a repo this
# org owns, by login and id.
site_github_org = "BooqyCustomers"
# Then, once every active restaurant with a domain has a deployed site repo
# (Website tab), serve each domain from its own site instead of the shared
# customer-front-end build:
per_tenant_sites          = true
site_link_prod_account_id = "343695380960"
# BooqyCustomers' numeric id (checked with the login before any role trust).
site_github_org_id = "356944191"

# Test sites (owner 2026-11-15, test-sites.tf): every customer created in THIS
# console is a test customer with a public repo site-<slug> in
# BooqyCustomersDev (App "Booqy Test Sites"), generated from the public
# BooqyCustomers/site-template.
# main -> https://<slug>.test.booqy.se, dev -> https://<slug>.test-dev.booqy.se,
# both in this account behind ONE standard CloudFront distribution (noindex)
# whose CloudFront Function maps the host to the customer's folder through a
# key value store. No distribution tenants (they cost money beyond 10 per
# account), nothing per customer that costs money.
# Phase 1: the two zones (about 1 USD/month for both, owner-approved). Phase 2
# (test_sites_enabled) on since 2026-11-15, after prod delegated them.
test_sites_zones         = true
test_sites_enabled       = true
test_sites_github_org    = "BooqyCustomersDev"
test_sites_github_org_id = "356983507"
site_template_owner      = "BooqyCustomers"

# AI phone agent (phone-agent.tf): the owner decided a cap of 2 concurrent
# executions on phone-agent-call in dev. The dev apply of 2026-11-05 was
# refused by AWS (InvalidParameterValueException: unreserved concurrency would
# fall below 10), so the dev account Lambda quota is below 12. Set to -1
# (unreserved) so dev can deploy; set back to 2 once the quota is raised.
# Prod is UNDECIDED (owner, before L goes live) and stays unreserved.
phone_agent_call_reserved_concurrency = -1

# In-app help assistant in Admin and Console (help-assistant.tf). On in dev,
# with Claude Haiku 5.5 on Bedrock through the EU inference profile (data stays
# in the EU); only the assistant uses the real model, meta-ads and
# site-builder stay on the simulator. Capped per tenant and platform
# (help_assistant_monthly_answers); answers come from the corpus alone past a cap.
help_assistant_enabled        = true
help_assistant_bedrock_client = "real"
help_assistant_model_id       = "eu.anthropic.claude-haiku-5-5"

# AI phone agent brain (owner 2026-11-13): Claude Haiku 5.5 on Bedrock (EU
# inference profile). The model client is real in dev, so the Telefon
# "Prova" simulator talks to the real model; voice and telephony stay
# simulators until the ElevenLabs and 46elks accounts exist.
agent_model_client   = "real"
phone_agent_model_id = "eu.anthropic.claude-haiku-5-5"
# The voice model whose languages a call may switch to (owner 2026-11-17: any
# language the caller speaks, Somali included). Inert for speech while
# voice_client is the simulator; the Prova simulator and the agent follow its
# language list. Verify the model in the ElevenLabs sandbox before prod.
phone_agent_tts_model = "eleven_v4_turbo"

# The AWS-only phone test line (owner 2026-11-13): Amazon Connect + Lex sv_SE +
# Polly Elin in Frankfurt, a real number that reaches the agent.
phone_test_line_enabled = true
phone_test_line_country = "FI" # no Swedish DID stock in Connect eu-central-1 (2026-11-13); FI keeps the call inside the EU price cap
# Restaurant 1 (tenant RADIN DJ AB, dev test data): tables and availability.
phone_test_line_location = { tenant_id = "01m4fqaga9r6s2e1pcx7t0wx3z", location_id = "01m4fqaga9ca7cfvybw0ptzezr" }

# Dev A2A test (owner 2026-11-20): Connect hands calls on the test line to the voice gateway on
# Fargate (a2a-dev-test.tf, about $0.095 per hour while on). Off until a test session.
a2a_dev_test_enabled       = true
a2a_dev_test_gateway_count = 1
a2a_dev_test_live          = false

# Billing (owner 2026-11-14): in advance on the 1st, the card charged
# automatically (emailed with 10 days until a card is added), reminders at
# 3, 7 and 14 days and a final notice at 30 to the restaurant and the
# operators, 60 kr reminder fee, förseningsersättning 450 kr less the
# reminder fee, interest reference rate + 8 %. Nothing is suspended
# automatically. The reference rate is 2.00 % for 1 July to 31 December 2026
# (riksbank.se); update it on 1 January and 1 July.
billing_suspend_after_days     = 0
billing_days_until_due         = 30
billing_days_until_due_no_card = 10
billing_reminder_steps         = [3, 7, 14]
billing_final_notice_days      = 30
billing_reminder_fee_sek       = 60
billing_late_fee_sek           = 450
billing_late_fee_after_days    = 7
billing_reference_rate_pct     = 2.0
# [NEEDS YOUR DETAILS] Booqy's address, organisation number, VAT number,
# registered office and F-skatt for the invoices (not secret). Dev invoices
# without them (the invoicing summary lists what is missing); prod refuses.
billing_seller = {
  name       = "IT Hjälparna Nordic AB"
  address    = "Vallmovägen 9, 612 46 Finspång"
  org_number = "559594-8810"
  vat_number = "SE559594881001"
  seat       = "Finspång"
  f_skatt    = true
}

# Dev twins (docs/DEV-TWINS.md): the owner login of every customer's dev
# twin (a Booqy team address, never the restaurant's) and the Stripe
# TEST-mode connected account the twins take payments with (test-pizza's,
# fully onboarded in test mode; an id, not a secret).
dev_twin_owner_email       = "aws+{slug}@ithjalparna.se"
dev_twin_stripe_account_id = "acct_1UVIUkHhsMKn0jQY"
# Prod's PUBLIC API and menu images (what any guest's browser reads): twins
# copy the real restaurant's public content from there, and a dev test
# customer may not take a slug a prod customer uses. Not secret.
dev_twin_prod_api_url   = "https://9md43vqnp1.execute-api.eu-north-1.amazonaws.com"
dev_twin_prod_image_url = "https://d3uasj29icofcs.cloudfront.net"

# Site languages (site-translate/): Amazon Translate budgets, new characters only
# (glossary and cache hits never count). Dev tests switch whole sites through
# every language again and again: 3,000,000 per restaurant per 30 days (about
# 45 USD at most), and the platform cap above it so it does not bind first.
site_translate_ip_requests_per_5min = 120
site_translate_ip_chars_per_hour    = 200000
site_translate_tenant_chars_per_30d = 3000000
site_translate_global_chars_per_30d = 5000000
