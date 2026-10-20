# Platform setup (once per environment)

What you do **once** for dev and once for production so that adding a restaurant
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
      Accounts v2 settings equivalent to *Standard* (`dashboard: full`,
      `fees_collector: stripe`, `losses_collector: stripe`): the restaurant has
      the full Stripe dashboard, pays Stripe's fees, and Stripe handles
      its losses and KYC.
- [ ] Settings → Connect → Branding: name, icon, colour - shown on the
      onboarding pages restaurants fill in.
- [ ] Accounts are created with **Accounts v2** (`POST /v2/core/accounts`):
      Stripe refuses v1 account creation for new Connect platforms. Leave
      "Accounts v1 support" (Settings → Developers → API policies) **off**.
- [ ] Sandbox (dev) and live (production) are separate: repeat the Connect
      setup in the sandbox.
- [ ] Keys - per environment (sandbox for dev, live for production):

| Key | Where | Needs |
|---|---|---|
| Pipeline key (`rk_...` or `sk_...`) | GitHub secrets `STRIPE_SECRET_KEY_DEV` / `STRIPE_SECRET_KEY_PROD` | Webhook Endpoints: Write, Connect → Accounts: Write (v1 + v2), Tax Rates: Write. Used by Terraform (webhook endpoints), the onboarding workflow (creating connected accounts + their VAT rates) and to seed the Lambda secret on first apply. |
| Lambda key (`rk_...`) | Secrets Manager `<env->stripe/api-key` as `{"apiKey":"rk_..."}` | Checkout Sessions, PaymentIntents, SetupIntents, Customers, Invoices, Invoice items, Credit notes, Refunds, Charges, Tax Rates: Write; Account Links: Write (v2); Accounts: Read; Terminal Locations + Readers: Write. Replace the seeded pipeline key after the first apply - Terraform never overwrites it. |
| Publishable key (`pk_...`) | `stripe_publishable_key` in `dev.tfvars` / `prod.tfvars` | Not secret. Websites get it from `GET /site-config`. |

  ```
  aws secretsmanager put-secret-value --secret-id dev-stripe/api-key \
    --secret-string '{"apiKey":"rk_test_..."}'      # production: stripe/api-key
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

## 2. SES (start early - the production account needs SES production access)

- [ ] Before a platform domain exists, mail goes from
      `NO_REPLY_EMAIL_ADDRESS` (`project.env`) - verify it in SES in both
      accounts.
- [ ] Production: request SES **production access** (sandbox only sends to
      verified recipients; ~24 h).
- [ ] Once the platform domain is live (§3) Terraform creates the
      `mail.<platform domain>` identity with DKIM, MAIL FROM and DMARC;
      sending switches to `noreply@mail.<platform domain>` automatically.
- [ ] Then set `cognito_invites_via_ses = true` in tfvars (once the
      sending domain is verified): both Cognito pools - restaurant owners/staff and you, the
      operators - email through SES (Cognito's own sender is capped at 50
      emails/day), and "Glömt lösenordet?" / "Forgot your password?" email
      a **link** to the app's reset page (custom message triggers,
      `compute/lambda/cognito-custom-message`). Without it the reset email
      shows a 6-digit code instead, which both apps also take. The first
      apply needs `iam:CreateServiceLinkedRole` (Cognito's SES email role);
      if the deploy role lacks it, run once:
      `aws iam create-service-linked-role --aws-service-name email.cognito-idp.amazonaws.com`.
      While an account's SES is in the sandbox, Cognito's emails only reach
      verified addresses and addresses on the verified sender domain.
- [ ] Once per environment: mark the existing restaurant users' emails
      verified - Cognito only sends a reset to a verified address, and
      staff invited before this release weren't marked (owners were).
      New invitations and email changes are marked automatically:
      ```bash
      POOL_ID=$(aws cognito-idp list-user-pools --region eu-north-1 --max-results 60 --query "UserPools[?Name=='<env->staff-user-pool'].Id | [0]" --output text)
      for U in $(aws cognito-idp list-users --region eu-north-1 --user-pool-id "$POOL_ID" --query "Users[].Username" --output text); do aws cognito-idp admin-update-user-attributes --region eu-north-1 --user-pool-id "$POOL_ID" --username "$U" --user-attributes Name=email_verified,Value=true; done
      ```
      (`dev-staff-user-pool` in dev, `staff-user-pool` in prod.)
- [ ] **SMS** (guest confirmations/reminders, when a restaurant turns SMS
      on): new accounts are in the SNS SMS sandbox and have a 1 USD/month
      SMS quota. Production: request SMS production access and a higher monthly
      quota (support case), then set `sms_monthly_spend_limit_usd` in
      prod.tfvars - Terraform sets the account's spend limit and alarms at
      80 % of it. Check the current limit first
      (`aws sns get-sms-attributes --region eu-north-1`): a lower value in
      tfvars stops SMS sooner. Unset (production today), the account's SMS
      settings are left alone and there is no spend alarm. SMS only go to
      Nordic numbers (+46, +45, +47, +358, +354); everyone else gets the
      email only.
      Food orders always send SMS (confirmation, "ready to collect") -
      not only when a restaurant turns booking SMS on. While dev is in
      the SMS sandbox, verify each test phone number first (it gets a
      one-time code):
      ```bash
      aws sns create-sms-sandbox-phone-number --region eu-north-1 --phone-number +46701234567 --language-code en-GB
      aws sns verify-sms-sandbox-phone-number --region eu-north-1 --phone-number +46701234567 --one-time-password 123456
      ```
- [ ] **Dev mail outbox** (until the platform domain is verified): with
      `mail_outbox = true` in dev.tfvars the notification Lambda saves
      every email to a private S3 bucket (`dev-mail-outbox-<account>`)
      instead of sending it, and copies every SMS there too (the SMS is
      still sent). Read them in Booqy Console → **Mail outbox** (HTML, text and
      every link in the message). Kept 30 days; can't be turned on in production
      (variable validation). Set it to `false` once
      `mail.dev.booqy.se` is verified to send for real.
- [ ] SES and SMS alarms (bounce rate, complaint rate, SMS spend) mail
      `alert_emails` - confirm the subscription email once.

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

- [ ] **BankID signing** (catering offers) - the secret
      `<env->catering/signing-provider` picks the provider
      (application `shared/bankid.py`):
  - **Quick dev test, no BankID at all** - the simulator (refused in
    production): signs as "Test Testsson" on the second status poll:
    `aws secretsmanager put-secret-value --region eu-north-1 --secret-id dev-catering/signing-provider --secret-string '{"provider":"simulator"}'`
  - **BankID test environment** (real BankID app in test mode): download
    BankID's public test RP certificate (`FPTestcert5_*.p12`, password
    `qwerty123`) and the test CA (`appapi2.test.bankid.com` server root)
    from bankid.com/utvecklare, convert and store:
    ```bash
    openssl pkcs12 -in FPTestcert5_20240610.p12 -passin pass:qwerty123 -nokeys -clcerts -out cert.pem -legacy
    openssl pkcs12 -in FPTestcert5_20240610.p12 -passin pass:qwerty123 -nocerts -nodes -out key.pem -legacy
    python3 -c 'import json;print(json.dumps({"provider":"bankid","environment":"test","certPem":open("cert.pem").read(),"keyPem":open("key.pem").read(),"caPem":open("ca.pem").read()}))' > signing.json
    aws secretsmanager put-secret-value --region eu-north-1 --secret-id dev-catering/signing-provider --secret-string file://signing.json
    rm cert.pem key.pem signing.json
    ```
    Then get a test BankID: the BankID app in test mode + a test
    identity from demo.bankid.com.
  - **Production**: BankID's rules don't allow one company's relying-party
    agreement to sign on behalf of other companies (the guest signs with
    *the restaurant*). Either a licensed signing provider (Idura / Scrive /
    Signicat - add it as a provider in `shared/bankid.py`) or written
    approval from your bank (SEB) for the platform setup, then
    `{"provider":"bankid","environment":"prod",...}` with the production
    certificate.
- [ ] **Cloudflare Turnstile** - one widget for the platform, used by the
      table booking form and the catering request form:
  - site key → `turnstile_site_key` in tfvars (websites get it from `/site-config`);
    once it is set, every online booking needs a valid token
    (`TURNSTILE_REQUIRED` on create-pending-reservation) - until then
    bookings are not bot-checked, so set it before launch;
  - secret → `<env->catering/turnstile` as `{"secretKey":"..."}`. Dev uses
    Cloudflare's test keys (dev.tfvars site key + the test secret written
    by security/secrets/catering), so nothing to set there;
  - hostnames: add the platform domain, and each restaurant's custom
    domain when it is attached (TENANT-ONBOARDING §5). Mind your
    Cloudflare plan's hostname-per-widget limit; past it, automate the
    list via the Cloudflare API or use a plan without hostname limits.

## 6. Repos and pipelines

- [ ] Push the Booqy Console repo (operator console: web app + the
      platform-tenants Lambda) to the GitHub org under exactly that name
      (the deploy role trusts it) and set its GitHub environment variables
      (Booqy Console README).
- [ ] Create the website template repo (e.g. `site-template`, marked as a
      GitHub template). Site repos must match `tenant_site_repo_pattern`
      (`site-*`).
- [ ] Push to `dev` → the pipeline applies, deploys placeholders. Merge
      to `main` for production.

## 7. Smoke test (dev, then production)

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
