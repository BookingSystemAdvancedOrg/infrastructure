# Platform setup (once per environment)

What you do **once** for dev and once for prod so that adding a restaurant
afterwards is code-less (`docs/TENANT-ONBOARDING.md`). Architecture:
`docs/MULTI-TENANCY.md`.

Steps 1, 2 and 5 involve third-party waiting periods - start them first.

---

## 1. Stripe platform account + Connect (start first)

Your company has **one** Stripe account - the platform. Every restaurant
gets its own connected account under it, created by the onboarding
workflow. You never handle a restaurant's keys.

- [ ] Your company's Stripe account: complete business verification.
- [ ] **Connect → Get started**: choose "platform/marketplace", complete
      the platform profile (live mode requires it before connected
      accounts can be created). Connected accounts are created with
      controller properties equivalent to *Standard*: the restaurant has
      the full Stripe dashboard, pays Stripe's fees, and Stripe handles
      its losses and KYC.
- [ ] Settings → Connect → Branding: name, icon, colour - shown on the
      onboarding pages restaurants fill in.
- [ ] Sandbox (dev) and live (prod) are separate: repeat the Connect
      setup in the sandbox.
- [ ] Keys - per environment (sandbox for dev, live for prod):

| Key | Where | Needs |
|---|---|---|
| Pipeline key (`rk_...` or `sk_...`) | GitHub secrets `STRIPE_SECRET_KEY_DEV` / `STRIPE_SECRET_KEY_PROD` | Webhook Endpoints: Write, Connect → Accounts: Write, Tax Rates: Write. Used by Terraform (webhook endpoints), the onboarding workflow (creating connected accounts + their VAT rates) and to seed the Lambda secret on first apply. |
| Lambda key (`rk_...`) | Secrets Manager `<env->stripe/api-key` as `{"apiKey":"rk_..."}` | Checkout Sessions, PaymentIntents, SetupIntents, Customers, Invoices, Invoice items, Credit notes, Refunds, Charges, Tax Rates: Write; Account Links: Write; Accounts: Read. Replace the seeded pipeline key after the first apply - Terraform never overwrites it. |
| Publishable key (`pk_...`) | `stripe_publishable_key` in `dev.tfvars` / `prod.tfvars` | Not secret. Websites get it from `GET /site-config`. |

  ```
  aws secretsmanager put-secret-value --secret-id dev-stripe/api-key \
    --secret-string '{"apiKey":"rk_test_..."}'      # prod: stripe/api-key
  ```

  If a restricted key gets permission errors on a Connect call, the
  Dashboard's error names the missing permission - add it, or use the
  account's secret key for the pipeline.

- [ ] Webhooks: nothing to do. Terraform creates the Connect endpoints
      (reservation, order, catering, `platform_connect`) and the platform
      billing endpoint with their signing secrets in Secrets Manager.
- [ ] VAT rates every restaurant gets (the catering flow needs them):
      once an accountant has confirmed them, set in both tfvars

  ```hcl
  default_tax_rates = {
    food = { display_name = "Moms", percentage = 12, inclusive = true }
  }
  ```

  Tenants onboarded before that: **Re-run provisioning** on their page in
  the operator app creates the missing rates.

## 2. SES (start early - prod needs production access)

- [ ] Before a platform domain exists, mail goes from
      `NO_REPLY_EMAIL_ADDRESS` (`project.env`) - verify it in SES in both
      accounts.
- [ ] Prod: request SES **production access** (sandbox only sends to
      verified recipients; ~24 h).
- [ ] Once the platform domain is live (§3) Terraform creates the
      `mail.<platform domain>` identity with DKIM, MAIL FROM and DMARC;
      sending switches to `noreply@mail.<platform domain>` automatically.
- [ ] Then set `cognito_invites_via_ses = true` in tfvars: owner/staff
      invitations go through SES (Cognito's own sender is capped at 50
      emails/day).

## 3. Platform domain (when decided)

Everything domain-related is off while `platform_domain` is empty - the
apps run on `*.cloudfront.net` and restaurants have no website URL yet.

- [ ] Buy/choose the domain (e.g. `bokning.example.se`) - a subdomain of a
      domain you own works too.
- [ ] Set `platform_domain = "bokning.example.se"` in the tfvars of the
      environment (dev typically uses a sub-zone, e.g. `dev.bokning.example.se`).
- [ ] Apply. The apply waits on certificate validation, so **delegate
      right away**: put the four `platform_domain_name_servers` output
      values as NS records at the registrar (or as an NS record in the
      parent zone for a subdomain). If the apply times out before
      delegation propagates, re-run it.
- [ ] Result: `app.<domain>` (restaurant admin), `ops.<domain>` (operator
      app), `<slug>.<domain>` per restaurant, custom domains via
      `tenant_domain_cname_target`, SES on `mail.<domain>`.
- [ ] Restaurants onboarded **before** the domain existed: **Re-run
      provisioning** on their page in the operator app gives them their
      `<slug>.<domain>` subdomain and placeholder site.

## 4. Operators

- [ ] `platform_operator_emails` in tfvars - each gets an email with a
      temporary password for the operator app. First sign-in: new
      password + authenticator app (MFA is mandatory).
- [ ] Removing an address deletes that operator on the next apply.

## 5. Catering third parties

- [ ] **BankID signing provider** (Scrive / Idura / Signicat) - one
      platform contract; register the `catering_signing_webhook_url`
      output as webhook URL; credentials per environment:
      `aws secretsmanager put-secret-value --secret-id <env->catering/signing-provider --secret-string '{"provider":"...","clientId":"...","clientSecret":"...","webhookSecret":"..."}'`
- [ ] **Cloudflare Turnstile** - one widget for the platform:
  - site key → `turnstile_site_key` in tfvars (websites get it from `/site-config`);
  - secret → `<env->catering/turnstile` as `{"secretKey":"..."}`;
  - hostnames: add the platform domain, and each restaurant's custom
    domain when it is attached (TENANT-ONBOARDING §5). Mind your
    Cloudflare plan's hostname-per-widget limit; past it, automate the
    list via the Cloudflare API or use a plan without hostname limits.

## 6. Repos and pipelines

- [ ] Push the `sbs-admin` repo (operator console: web app + the
      platform-tenants Lambda) to the GitHub org under exactly that name
      (the deploy role trusts it) and set its GitHub environment variables
      (sbs-admin README).
- [ ] Create the website template repo (e.g. `site-template`, marked as a
      GitHub template). Site repos must match `tenant_site_repo_pattern`
      (`site-*`).
- [ ] Push to `dev` → the pipeline applies, deploys placeholders. Merge
      to `main` for prod.

## 7. Smoke test (dev, then prod)

- [ ] Sign in to the operator app; create a test tenant with your own
      email as owner → status `active` within a minute.
- [ ] Sign in to the admin app as that owner; Settings → Payments →
      complete Stripe test onboarding (sandbox: use the test data Stripe
      pre-fills) → "Online payments active".
- [ ] Create a location; second location is refused on a 1-location plan;
      change the plan in the operator app → allowed immediately.
- [ ] Order end-to-end on the tenant site (`4242 4242 4242 4242`) - the
      payment appears in the **connected** account's dashboard.
- [ ] Create a second tenant; with tenant A's token, call tenant B's
      location ids → 404.
- [ ] Suspend tenant A → its users are signed out, its site's
      `/site-config` returns 404. Resume.
- [ ] All `*-dlq` queues empty; no `tenant-*-timed-out` alarm.
