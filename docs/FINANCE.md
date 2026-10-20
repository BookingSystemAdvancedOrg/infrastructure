# Finance: subscription invoicing and the Finance page

What every customer pays and what they cost, per day, and how Booqy
Console shows it. Code: `payments/billing` (Stripe catalog),
`storage/dynamodb/finance` (the table), `compute/lambda/finance-rollup`
(the nightly job, code in the application repo), platform-stripe-webhook
(`/billing` events, application repo), platform-tenants (console API,
booqy-console repo: `billing.py`, `finance.py`).

## 1. Subscriptions: Stripe Billing on the platform account

Every restaurant company (tenant) is a **Stripe Customer** on YOUR
platform account with one **Subscription** on its plan's monthly price.
This has nothing to do with the restaurant's Connect account (guest
payments), which stays as it is.

| Piece | Where |
|---|---|
| Plans and prices | `var.plans` (tfvars): `price_sek` per month excluding VAT. `payments/billing` creates one `stripe_product` + monthly `stripe_price` per plan and the Swedish VAT rate (`Moms`, 25 %, exclusive). The ids land on the `PLAN#` rows (`priceSek`, `stripePriceId`) and in platform-tenants' env (`BILLING_TAX_RATE_ID`). |
| Price change | A new Stripe price (amounts are immutable); the old one is archived. Running subscriptions keep their price until the customer's plan is saved again in Booqy Console, or until **Update to the plan price** on the Billing tab. |
| Customer + subscription | Booqy Console: on the **New customer** form (section 4b, "Start invoicing when the customer is created", on by default) or later from the customer page's **Billing** tab. A future first invoice date is a Stripe trial until then. The console creates the Stripe customer (legal name, billing email, address, VAT number as `eu_vat`, `metadata.tenantId`), claims `STRIPE_CUSTOMER#<cus> / TENANT` in the tenant table and writes `PROFILE.billing`. |
| Own price | The form and the Plan tab take a monthly price (SEK ex VAT). The plan's price uses the plan's Stripe price; a different amount becomes a price on the plan's product (`price_data`, `stripeProductId` on the PLAN row) and is stored as `billing.priceSek`. |
| Terms | `billing.terms`: **try-out** (default on the form): pays monthly, can leave at the end of any paid month, becomes a subscription by itself after `billing_trial_months` (6) or when converted from the Billing tab; **subscription**: `billing_notice_months` (3) months' notice. Stored with `termsSince`; the daily task does the conversion. |
| Cancellation | Billing tab, **Cancel subscription**: Stripe `cancel_at` = the end of the paid month (try-out) or that plus the notice months (subscription); the customer is invoiced until then. "Offboard automatically when it ends" (default on) makes the daily task offboard the customer the day after Stripe has ended the subscription (`billing.offboardAtEnd`). **Keep the subscription** undoes it; "End today" is the immediate cancel with a final prorated invoice. |
| Collection | `send_invoice` (default): Stripe emails the invoice, due in `billing_days_until_due` (30) days; paid by card on the hosted invoice page, or by bankgiro to your own account, in which case you mark the invoice paid in Stripe (`paid_out_of_band`). `charge_automatically`: after the restaurant added a card through a **card link** (Stripe Checkout in setup mode) and **Charge the card** on the Billing tab. Stripe's own bank transfers do not support SEK. |
| Plan change | `PUT .../plan` (with the optional own price) moves the subscription item to the new price **from the next invoice** (no proration: the paid month stays as it is). Extra-location overrides are not priced. |
| Suspend / resume | Leave the subscription alone (a suspended customer still owes). **Pause invoicing** / **Resume invoicing** on the Billing tab is a separate action (`pause_collection`). |
| Offboarding | The console cancels a still running subscription at once with a final prorated invoice, then starts the offboarding workflow (the daily task does the same for an ended subscription marked to offboard). A Stripe failure is reported and does not block offboarding. The Stripe customer and the invoices are never deleted (bookkeeping); tenant-purge touches neither Stripe nor the finance table. |
| Unpaid invoice | The daily **dunning task** (platform-tenants, `{"financeTask": "dunning"}`, `billing_dunning_schedule`) works every open invoice through Stripe: **reminders** from the day after the due date and every `billing_reminder_interval_days` (7) days, as Stripe re-sends of the invoice email (`POST /invoices/{id}/send`; card-charged invoices are left to Smart Retries); the **late fee** `billing_late_fee_sek` (450 kr, VAT-free, förseningsavgift) once per invoice still unpaid `billing_late_fee_after_days` (7) days after the due date, as an invoice item on the customer that lands on their next invoice; **interest** (dröjsmålsränta) when a late invoice is paid: the overdue amount at `billing_reference_rate_pct` + `billing_interest_margin_pct` (8) per year for the days late, as a VAT-free invoice item; a customer without a running subscription gets a one-off invoice for the items at once. Every step is recorded on the ledger row (`remindersSent`, `lastReminderAt`, `lateFeeAdded`, `interestAdded`), so a re-run never repeats it. `invoice.payment_failed` sets `billing.pastDueSince`; customers past due longer than `billing_suspend_after_days` (14; 0 = never) are suspended exactly like Suspend in the console and resumed when they pay. The operators get one email per run that did something. **Payments** on the Finance page shows who has paid for a month, with days late, reminders and fees, and a Send reminder button. |

### Webhook (`platform-stripe-webhook`, path `/billing`)

The platform billing endpoint (`payments/stripe`, `platform_billing_events`):

| Event | Effect |
|---|---|
| `customer.subscription.created/updated/deleted` | `PROFILE.billing`: status, price, plan, `mrrSek`, period, pause, `pastDueSince` (set on past_due/unpaid, cleared on active) |
| `invoice.finalized`, `invoice.paid`, `invoice.payment_failed`, `invoice.voided`, `invoice.marked_uncollectible` | finance table: the invoice row (`INVOICE#<created day>#<in_...>`) and the day's `invoicedSek` (finalized), `paidSek` (paid), reversal (voided); `lastPaidAt` / `lastPaymentFailedAt` on the profile |
| `credit_note.created` | finance table: `CREDIT#...` row and `creditedSek` on the day |

The customer resolves through `STRIPE_CUSTOMER#<cus>`; every profile
write is conditional on `billing.customerId` still being that customer
and on the event being newer than the last applied one. Revenue is booked
once per invoice and kind (flags on the ledger row in the same
transaction as the ADD), so redeliveries never double count. Amounts are
SEK excluding VAT. Live events reaching dev (and the reverse) are ignored.

## 2. AWS cost per customer: allocated, not tagged

Everything is shared (one API, one set of Lambdas, DynamoDB on demand, one
CloudFront), so cost per customer is a split, not a measurement.

- **Source:** `finance-rollup` calls Cost Explorer (`ce:GetCostAndUsage`,
  daily, grouped by service, `UnblendedCost`, credits and refunds excluded)
  for the last `COST_DAYS` (7) days every night, because AWS restates
  recent days. Stored as `PLATFORM / COST#<day>` with the rate used.
  Cost Explorer must be **enabled once per account** (open it in the
  console; the API answers after about 24 hours); until then the job
  warns and cost is 0. About $0.01 per API call.
- **Currency:** USD from AWS, shown in SEK with `aws_usd_to_sek` (tfvars).
  The rate is recorded on every cost row; changing it applies from the
  next run (Rebuild recomputes a range).
- **Buckets** (`cost_allocation`, tfvars): `baseline` services (Route 53,
  Secrets Manager, KMS, ECR, Config, CloudTrail, Support, Tax, ...) are
  split equally over the customers active that day; `email` (SES) by
  emails sent; `sms` (SNS) by SMS sent; every other service (Lambda, API
  Gateway, DynamoDB, CloudFront, Cognito, S3, CloudWatch, Step Functions,
  ...) by API requests. A bucket nobody used that day falls back to an
  equal split, so cost never disappears. Move a service between lists
  without a code change.
- **Usage counters:**
  - *requests*: `shared/tenant.py` logs `TENANT_REQUEST tenant=<id>
    loc=<locationId or -> kind=jwt|public` once per resolved request in
    every tenant-aware Lambda; the job counts them per customer and
    location with one CloudWatch Logs Insights query per 20 log groups
    (`local.tenant_aware_log_groups`). Nothing is written on the request
    path. Backfill is limited to the 30-day log retention.
  - *bookings*, *orders*: the day's `RESERVATION#<day>#` and `ORDER#<day>#`
    rows per location (holds, pending guarantees, unpaid and cancelled
    orders excluded). The day is the visit / order date.
  - *emails*, *sms*, *marketingEmails*: `notification` and
    `marketing-send` do `ADD` on the customer's day row per message
    (`shared/finance.py`). Not counted: platform news from the Mail page.
- **Active on a day:** from `createdAt` until the day of `offboardedAt`;
  suspended customers count (the platform still serves them);
  provisioning ones do not.

## 3. The finance table

`storage/dynamodb/finance` (`<env->finance`), on demand, PITR, never purged:

| PK | SK | Written by | Fields |
|---|---|---|---|
| `TENANT#<id>` | `DAY#<yyyy-mm-dd>` | finance-rollup (`requests`, `bookings`, `orders`, `costSek`, `costSplitSek`, `mrrSek`, `planId`, `active`); senders (`emails`, `sms`, `marketingEmails`, ADD); webhook / Stripe import (`invoicedSek`, `paidSek`, `creditedSek`, ADD) | one row per customer and day |
| `TENANT#<id>` | `LOC#<locationId>#DAY#<yyyy-mm-dd>` | finance-rollup (`requests`, `bookings`, `orders`, `costSek`: the location's share of the customer's cost, by requests, else bookings and orders, else equally); senders (`emails`, `sms`, ADD) | one row per location and day; the Finance page's location filter (revenue stays the customer's) |
| `TENANT#<id>` | `INVOICE#<day>#<in_...>` | webhook, Stripe import | status, amounts ex and incl VAT, dates, links, booking flags |
| `TENANT#<id>` | `CREDIT#<day>#<cn_...>` | webhook | credit notes |
| `PLATFORM` | `COST#<day>` | finance-rollup | USD by service, rate, SEK |
| `PLATFORM` | `DAY#<day>` | finance-rollup | customers active / new / churned, MRR, cost, usage and revenue totals |
| `PLATFORM` | `JOB#latest`, `JOB#<time>` | finance-rollup | last run, days done, warnings |

Day is the grain: week, month, quarter, year and any range are sums over
`DAY#` rows (one Query per customer). MRR on the Finance page is the
live figure from `PROFILE.billing`; the `mrrSek` on day rows is the
snapshot behind the MRR trend chart.

## 4. Jobs and schedules

| What | Where | When |
|---|---|---|
| finance-rollup | `compute/lambda/finance-rollup`, role `security/iam/finance-rollup`, code `application/functions/finance-rollup` | `finance_rollup_schedule` (04:30 UTC). Also `{"from","to"}` from Booqy Console's **Rebuild** (max 92 days, yesterday at the latest) and self-continuation near its timeout |
| dunning | platform-tenants `{"financeTask": "dunning"}`, role `security/iam/scheduler-invoke-platform-tenants` | `billing_dunning_schedule` (05:00 UTC): reminders, late fee, interest, past-due suspension and resumption, try-out conversion after `billing_trial_months`, offboarding of ended subscriptions |
| webhook | platform-stripe-webhook `/billing` | on every Stripe event |
| Stripe import | Booqy Console, Finance page, **Import from Stripe** (`POST /platform/finance/stripe-sync`) | by hand: re-reads every customer's subscription and invoices (missed webhooks) |

Warnings (Cost Explorer not enabled, a log query that failed, a day
that errored) go to the alert topic once per run and are shown on the
Finance page.

## 5. IAM (what each role got)

- `finance-rollup` (new): `ce:GetCostAndUsage` (*), `logs:StartQuery` /
  `StopQuery` on the tenant-aware Lambdas' log groups and
  `logs:GetQueryResults` (*), Query/GetItem on the tenant table (GSI1),
  Query on location, reservation and order tables, read/write on the
  finance table, `sns:Publish` on the alert topic, `lambda:InvokeFunction`
  on itself.
- `scheduler-invoke-finance-rollup`, `scheduler-invoke-platform-tenants`
  (new): EventBridge Scheduler roles for the two schedules.
- `platform-tenants`: finance table read/write, `lambda:InvokeFunction` on
  finance-rollup (Rebuild), `sns:Publish` on the alert topic (dunning).
- `platform-stripe-webhook`: finance table GetItem/PutItem/UpdateItem.
- `notification`, `marketing-send`: `dynamodb:UpdateItem` on the finance
  table (counters).

No OIDC / deploy role changed: the application deploy role already covers
every `<env>-*` function and ECR repository.

### Customer terms

The late fee and the interest are the statutory defaults for a company
customer in Sweden (lag 1981:739 om ersättning för inkassokostnader §4a,
räntelagen §6), but say so in the customer contract: payment terms 30
days, förseningsavgift 450 kr, dröjsmålsränta referensränta + 8 %. Update
`billing_reference_rate_pct` in tfvars when the Riksbank sets a new
reference rate (1 January and 1 July).

## 6. Hand set-up (Terraform cannot)

Stripe Dashboard, once per mode (sandbox and live):

- Billing → Settings → **Subscriptions and emails**: send finalized
  invoices and receipts to customers, reminders before and after the due
  date, Smart Retries for card payments, and what happens when retries
  fail (leave the subscription past due; the dunning task here suspends
  the customer after `billing_suspend_after_days`).
- Billing → Settings → **Invoice template**: your company name, address,
  org. number, "Godkänd för F-skatt", and the bankgiro number in the
  footer for customers who pay by bank transfer. Set the numbering
  prefix you want on the invoices.
- Optional: the customer portal, if restaurants should see their
  invoices and change their card themselves (the console does not use it).

AWS, once per account: open **Cost Explorer** in the console to enable it
(the API answers after about 24 hours).

tfvars, per environment: `plans.<id>.price_sek` (the placeholders in
dev.tfvars / prod.tfvars), `aws_usd_to_sek`, and if wanted
`billing_days_until_due`, `billing_suspend_after_days`, `cost_allocation`.
