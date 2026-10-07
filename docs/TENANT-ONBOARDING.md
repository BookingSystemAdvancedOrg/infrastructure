# Adding a restaurant (tenant)

The per-customer runbook. **No code, no Terraform, no deploy** - everything
here happens in the operator app (`platform_admin_app_url` output), the
restaurant's own Stripe account, and DNS. One-time platform setup is in
`docs/PLATFORM-SETUP.md`; how it works is in `docs/MULTI-TENANCY.md`.

(This replaces the old fork-per-customer runbook: one deployment now
serves every restaurant.)

---

## 1. Create the tenant (2 minutes)

Operator app → **New tenant**: restaurant name, slug (becomes
`<slug>.<platform domain>`), owner's email + name, plan, optionally legal
name / org number / contact email.

The onboarding workflow then, in about a minute:

- invites the owner (email with a temporary password, linking to the admin app);
- creates the restaurant's Stripe connected account and its VAT rates;
- gives it `<slug>.<platform domain>` with a "coming soon" page
  (once a platform domain is set);
- sets the tenant `active`.

`provisioning_failed` → the tenant page shows the error, and an alert
email goes out. Fix the cause (e.g. a Stripe key permission) and press
**Retry onboarding** - every step is idempotent.

## 2. The owner sets up payments (restaurant, ~15 minutes + Stripe review)

The owner signs in to the admin app → **Settings → Payments → Set up
payments** and fills in Stripe's onboarding (company, bank account, ID).
Status shows "Online payments active" once Stripe enables charges -
usually minutes, sometimes a review of a few days. Until then the
restaurant's online payments return "temporarily unavailable"; everything
else works.

If you do it together on a call: operator app → tenant → Payments →
**Create onboarding link** (expires within minutes - open it right away).

Then, in **their own Stripe dashboard** (they have full access):

- [ ] Payment methods: card + Klarna + Swish (Swish needs a Swedish org
      and SEK). Reservations stay card-only by design.
- [ ] If they use catering, before the first catering order:
  - Settings → Billing → Invoices: account-level sequential numbering, prefix;
  - Settings → Business → public details: legal name, address, org/VAT
    number; "Godkänd för F-skatt" in the default invoice footer;
  - Settings → Branding: logo and colours (invoices, Checkout);
  - Billing → Emails: send finalized invoices, receipts and reminders;
  - Billing → Automatic collection: keep past-due invoices open.

Refunds, payouts and disputes are handled in their dashboard - the money
is theirs, not routed through you.

## 3. The owner sets up the restaurant (admin app)

- [ ] Settings → Profile: sender name (email + SMS), reply-to address,
      branding.
- [ ] Create the location(s) (as many as the plan allows), menu, table
      layout, catering settings.
- [ ] Invite staff (Users).

## 4. Website

- [ ] GitHub: **Use this template** on `site-template` → new repo
      `site-<slug>` (the name must match `site-*`).
- [ ] Set `TENANT_ID` (from the tenant page) in its pipeline, build the
      site, push - it publishes to `<slug>.<platform domain>`, replacing
      the placeholder. Details: `docs/handoff/FRONTEND.md` §3.

## 5. Custom domain (optional)

- [ ] Operator app → tenant → Domains → **Add domain**
      (e.g. `www.restaurang.se`, tick "primary" to use it in links/emails).
- [ ] Send the restaurant the DNS record shown:
      `www.restaurang.se CNAME <tenant_domain_cname_target>`.
      Bare `restaurang.se`: most DNS hosts can't CNAME the apex - redirect
      it to `www.` at the registrar, or use a DNS host with ALIAS/ANAME.
- [ ] Status goes `pending_dns` → `pending_validation` → `active`
      (certificate issued and renewed by CloudFront, nothing to import).
      The workflow waits up to ~3 days for the CNAME (`validation_timeout`
      after that - fix the DNS and **Add domain** again; it resumes).
- [ ] Add the domain to the platform's Turnstile widget hostnames in
      Cloudflare (catering request form) - the one manual step.

No Route 53 import: the restaurant keeps its domain wherever it is
registered; only the one CNAME points at the platform.

## 6. Upgrade / downgrade

Operator app → tenant → **Plan**: pick the plan or override
max locations / features. Takes effect immediately - "2 locations instead
of 1" is this one action. Lowering below the current number of locations
asks for confirmation; existing locations keep working, new ones are
blocked.

## 7. Suspend / resume

**Suspend** (e.g. unpaid subscription): all its users are signed out and
can't sign in, the API refuses its admin calls, the website shows
"unavailable", its public endpoints return 404. Data, Stripe account and
domains stay. **Resume** reverses it.

## 8. Offboarding

**Offboard** (type the slug to confirm): users disabled and signed out,
custom and platform domains detached from CloudFront (certificates
deleted), tenant marked `offboarded`. Kept on purpose:

- their data in DynamoDB (export on request, then delete by `tenantId` /
  `TENANT#<tenantId>` keys);
- catering documents - 7-year Object Lock (bookkeeping law), can't be
  deleted before expiry;
- their Stripe account - it's theirs; they can disconnect the platform in
  their Stripe dashboard;
- the website files under `tenant-sites/<tenantId>/` (versioned bucket) -
  delete the prefix once the data request is settled; archive the
  `site-<slug>` repo.

## 9. Things that are not per-tenant anymore

No new AWS accounts, no fork, no GitHub secrets, no SES verification, no
Stripe keys, no Terraform change. If you find yourself doing any of those
for a restaurant, something belongs in the platform instead.
