# Deploying this stack for a new customer

One customer = one fork of the four repos = two fresh AWS accounts (dev +
prod) = one Stripe account. A customer fork's diff from upstream is **only**
`.github/config/project.env`, the `*.tfvars` files, and GitHub secrets —
never Terraform edits. Customer-specific behavior becomes a variable in
upstream, not a patch in a fork; that rule is what keeps
`git merge upstream/main` conflict-free for every customer forever.

Do the steps in order. Steps 1 and 6 involve third-party waiting periods —
start them first.

---


## 1. SES email (start first — has a waiting period)

- [ ] Decide the customer's no-reply address (e.g. `noreply@customer.se`)
- [ ] In **each** AWS account (after step 2), verify the domain in SES and
      add the DNS records
- [ ] Request SES production access in the **prod** account (new accounts
      are sandboxed to verified recipients only; approval takes up to ~24h)

## 2. AWS accounts

- [ ] Create two member accounts in the AWS Organization:
      `<customer>-dev` and `<customer>-prod`
- [ ] Note both 12-digit account IDs
- [ ] Set up billing alarms/budgets per account

## 3. GitHub

- [ ] Create the customer's GitHub organization
- [ ] Fork all four repos into it: `infrastructure`, `application`,
      `customer-front-end`, `admin-front-end`
- [ ] In the infrastructure fork, add the `dev` branch (dev pipeline
      triggers on pushes to `dev`, prod on pushes to `main`)

## 4. Vend the AWS accounts' pipeline plumbing (aws-accounts repo)

The state bucket, GitHub OIDC provider, and infra deploy role for each
account come from the separate **aws-accounts** repo (the account-vending
layer), NOT from this repo - the pipeline here can only run once they
exist.

- [ ] In the aws-accounts repo, vend the new customer's OU/accounts with
      their pipeline plumbing (dev + prod)
- [ ] Make sure the vended infra role's trust policy is parameterized with
      THIS customer's GitHub org and infrastructure repo name - each fork
      lives under a different org, so a role pinned to another org's repo
      can never be assumed by this one
- [ ] Record each account's infra role ARN and state bucket name for step 5

## 5. Configure the infrastructure fork

- [ ] Edit `.github/config/project.env` — every value in it is
      customer-specific: the two `OIDC_ROLE_ARN_*` and
      `TERRAFORM_STATES_BUCKET_NAME_*` values from step 4, `AWS_REGION`,
      `NO_REPLY_EMAIL_ADDRESS`, `GITHUB_ORG`, and the three repo names
- [ ] Edit `dev.tfvars` / `prod.tfvars` — `super_admin_emails` for this
      customer's admins

## 6. Stripe (per customer — their own Stripe account)

- [ ] Customer signs up at stripe.com; complete business/identity
      verification (Stripe's review can take days — start early)
- [ ] Make sure a **sandbox** exists (environment picker, top-left of the
      Dashboard — use the default one or click Create sandbox once; older
      accounts show classic "test mode" instead, which just exists).
      Sandboxes can't be created by Terraform — Terraform works *inside*
      whichever environment its API key belongs to
- [ ] In the **sandbox / test mode**: create a restricted key (Checkout
      Sessions: Write, Webhook Endpoints: Write) → GitHub secret
      `STRIPE_SECRET_KEY_DEV`
- [ ] In **live mode**: same restricted key → `STRIPE_SECRET_KEY_PROD`
- [ ] Activate the customer's payment methods (Settings → Payment
      methods): card + Klarna + Swish for orders. Swish requires a Swedish
      org and SEK; Klarna activates per market. Reservations stay
      card-only by design — see docs/RESERVATION-PAYMENT-FLOW.md
- [ ] Nothing else — webhook endpoints and their signing secrets are
      created and wired by Terraform (`payments/stripe`) on every apply

## 7. First deploy

- [ ] Open a PR to `dev` first and **read the plan** — the cheapest place
      to catch a mistyped project.env value
- [ ] Push/merge to `dev` → pipeline applies, pushes placeholder Lambda
      images, deploys placeholder front-ends
- [ ] Verify: pipeline green; `stripe_webhook_urls` output populated; both
      webhook endpoints visible in the customer's Stripe test-mode
      Dashboard; placeholder front-end loads over CloudFront
- [ ] Wire up the other three forks' pipelines (they assume the app deploy
      roles this apply just created) and deploy the real images/front-ends
- [ ] Merge to `main` → same for prod, against Stripe live mode

## 8. Smoke test (dev, then prod)

- [ ] Log in with a bootstrap super-admin (temp password:
      `terraform output -raw super_admin_temp_password`), rotate it
- [ ] Create a location, a menu item with an image, a reservation
- [ ] Place a test order end-to-end: order → Stripe Checkout (test card
      `4242 4242 4242 4242`) → order flips to confirmed via webhook
- [ ] Abandon a checkout and confirm the order is cancelled when the
      session expires

## Offboarding a customer

Empty and delete both state buckets **manually** (they're
`prevent_destroy`), `terraform destroy` per environment, close the AWS
accounts, customer keeps their Stripe account. Their data never shared an
account with anyone else's — that's the point of this model.
