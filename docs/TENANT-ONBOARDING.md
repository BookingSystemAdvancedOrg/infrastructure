# Adding a restaurant (tenant)

The per-customer runbook. **No code, no Terraform, no deploy** - everything
here happens in the operator app (`platform_admin_app_url` output), the
restaurant's own Stripe account, and DNS. One-time platform setup is in
`docs/PLATFORM-SETUP.md`; how it works is in `docs/MULTI-TENANCY.md`.

(This replaces the old fork-per-customer runbook: one deployment now
serves every restaurant.)

---

## 1. Create the tenant (2 minutes)

Operator app → **New tenant**: restaurant name, slug (an internal id;
`<slug>.<platform domain>` only if `tenant_subdomains_enabled`), owner's
email + name, plan, legal name / org number / contact email (the org
number and address are needed later to buy a .se domain).

The onboarding workflow then, in about a minute:

- invites the owner (email with a temporary password, linking to the admin app);
- creates the restaurant's Stripe connected account and its VAT rates;
- gives it `<slug>.<platform domain>` (only with `tenant_subdomains_enabled`
  - off: restaurants are reached on their own domain, step 5);
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

Nothing to build: every restaurant is served by the same customer site
(customer-front-end), which looks up the restaurant from the domain it is
opened on (`GET /site-config?host=`). It goes live with step 5.

## 5. Domain

Operator app → tenant → **Domains** → **Add domain**. Three ways:

**Buy a new domain** (.se, .com, .eu, .net - Route 53 Domains, billed to
the platform's AWS account, auto-renews yearly):

- [ ] Search the name - availability, first-year and renewal price (USD).
- [ ] Check the registrant: the restaurant's AB (legal name, org number,
      address, contact person, email, phone - prefilled from the profile).
      The restaurant owns the domain; we hold it in our account.
- [ ] **.se only:** upload the company's **registreringsbevis** (PDF from
      Bolagsverket, max 10 MB). Required - the .se registry verifies the
      owner (NIS2) before the domain goes live.
- [ ] Confirm the price → **Buy**. Non-refundable.
- [ ] **.se only:** status `awaiting_verification`. Open an AWS Support case
      (Route 53 Domains → Domain registration) with the text the Console
      shows and attach the registreringsbevis (download link on the domain
      row). The workflow checks every hour for up to 30 days and carries on
      by itself once the registry approves; the file is deleted then
      (and in any case after 30 days).
- [ ] Then automatically: `registered` → `attaching` (certificates for
      `restaurang.se` and `www.restaurang.se`) → `live`.

**Connect a domain the restaurant already has** (stays at one.com etc.;
we take over its DNS - the bare domain works too):

- [ ] Enter the domain → **Scan DNS**: the records it uses today (mail,
      SPF/DKIM/DMARC, Microsoft 365/Google…). Check the list with the
      restaurant - anything missing (other DKIM selectors, custom
      subdomains) add by hand. A record left out stops working when the
      name servers change; email is the usual casualty.
- [ ] **Connect** → creates the Route 53 zone with those records and shows
      four name servers.
- [ ] The restaurant replaces the name servers at its registrar with
      those four (and turns DNSSEC off there first, if it's on). Status
      `awaiting_nameservers`; checked every 10 minutes for 72 h.
- [ ] Then automatically: `attaching` → `live`. No registreringsbevis -
      nothing changes at the registry.

**Just a CNAME** (advanced - the restaurant keeps its DNS):

- [ ] Add e.g. `www.restaurang.se`, send them
      `www.restaurang.se CNAME <tenant_domain_cname_target>`. The bare
      domain can't be a CNAME - redirect it to `www.` at the registrar.
      `pending_dns` → `pending_validation` → `active`; waits up to ~3 days
      (`validation_timeout` after that - fix the DNS and add it again).

For every domain:

- [ ] Add it (and `www.`) to the platform's Turnstile widget hostnames in
      Cloudflare (table booking and catering request forms). Without it
      guests on that domain can't book online.

**Move a connected domain's registration into Route 53** (optional, once
it's `live` - one bill, renewals handled by us; .se/.com/.eu/.net only):

- [ ] Ask the restaurant for the domain's **authorization code** (one.com:
      *Domain → Transfer / EPP code*; also called auktoriseringskod) and to
      unlock the domain if their registrar locks it. Not possible within 60
      days of registering or a previous transfer.
- [ ] Domains → the domain → **Transfer to Route 53** → check (shows if it
      can move and the price - it includes one more year), registrant (the
      AB), **registreringsbevis for .se** (required), the code, confirm.
- [ ] Status shows under the domain: `transferring` (the old registrar
      releases it - usually up to 5-7 days; approving the email from one.com
      speeds it up) / `awaiting_verification` (.se: send the AWS Support
      case, same as buying) → `transferred`. Name servers are kept, so the
      site and email never notice; a failed transfer just leaves the domain
      where it was.
- [ ] Once transferred, the restaurant can drop the *domain* from its
      one.com plan - but must keep any *email* subscription there if their
      MX records still point at one.com.

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
