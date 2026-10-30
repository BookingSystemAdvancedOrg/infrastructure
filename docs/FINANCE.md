# Finance: invoicing in arrears and the Finance page

What every customer pays and what they cost, per day, and how Booqy
Console shows it. Code: `payments/billing` (Stripe VAT rate and plan catalog),
`storage/dynamodb/finance` (the table), `compute/lambda/finance-rollup`
(the nightly job, code in the application repo), platform-stripe-webhook
(`/billing` events, application repo), platform-tenants (console API,
booqy-console repo: `billing.py`, `finance.py`).

## 1. The agreement: one invoice per period, in arrears

Every restaurant company (tenant) is a **Stripe Customer** on YOUR
platform account. There is no Stripe subscription: the platform keeps the
agreement itself (`PROFILE.billing`) and builds one Stripe invoice per
billing period, after the period, from its own figures. Nobody pays in
advance. This has nothing to do with the restaurant's Connect account
(guest payments), which stays as it is.

| Piece | Where |
|---|---|
| Billing period | The 25th of one month to the 24th of the next. SMS parts are counted on the Swedish calendar day (`shared/finance.py billing_day`), so an SMS at 00:30 on the 25th is in the new period. The **invoicing run** (`billing_invoicing_schedule`, daily 05:30 UTC, platform-tenants `{"financeTask": "invoice"}`, after finance-rollup and dunning) invoices on the 25th the period that ended the day before; on any other day it only catches up a complete period not yet invoiced (a failed or unfinished run), so a Stripe outage on the 25th is invoiced the next morning. A run stops starting restaurants 30 s before the Lambda timeout (300 s) and lists them as "not reached"; the alarm `platform-tenants-errors` emails the operators when a run crashes or times out. Helpers `period_of`, `next_period`, `active_days`, `fee_for` in the console API's `billing.py`, the same in `web/src/finance.ts`. |
| Agreement | `PROFILE.billing`: `status` active \| ended, `startsAt`, `endsAt`, `terms` trial \| subscription with `termsSince`, `priceSek` (the customer's own monthly price), `smsPriceSek` (own SMS price), `collectionMethod`, `lastInvoicedPeriodEnd`, `offboardAtEnd`, `customerId`. The console shows the phase: none, scheduled (starts later), active, ending (`endsAt` set), ended. Started from the **New customer** form (section 4b) or the customer page's **Billing** tab with a start date; the console creates the Stripe customer (legal name, billing email, address, VAT number as `eu_vat`, `metadata.tenantId`) and claims `STRIPE_CUSTOMER#<cus> / TENANT` in the tenant table. |
| The invoice | Two invoice items on the customer, then `POST /invoices` with `pending_invoice_items_behavior=include`, finalize and send (or pay). **The monthly price**: `var.plans.price_sek` or the customer's own `priceSek`, pro rata by active days when the agreement started or ended inside the period ("Booqy Starter, 25 aug till 24 sep 2026 (15 av 31 dagar)"). **One SMS line**: the period's `smsParts` from the customer's day rows times the SMS price, with the split per location in the text ("SMS 25 aug till 24 sep 2026: 412 delar x 0,70 kr (Roma Södermalm 300, Roma Vasastan 112)", `quantity` and `unit_amount_decimal`). Both carry the 25 % VAT rate and `period[start/end]`; `metadata.kind` fee \| sms and `periodEnd` on the items, `kind` period, `periodStart` / `periodEnd` on the invoice. No VAT rate (`BILLING_TAX_RATE_ID` empty) = no invoice, reported as failed. A month with nothing to pay (price 0, no SMS or SMS price 0) gets no invoice. A re-run never invoices a period twice: `lastInvoicedPeriodEnd` on the profile, the ledger row, then Stripe itself (the customer's invoice with that `periodEnd`, and its pending items, are looked up before anything is created, so a run that stopped half way is finished, not repeated, also after Stripe's 24-hour window for the idempotency keys `fee-<tenant>-<periodEnd>`, `sms-...`, `inv-...`). |
| SMS price | `sms_price_sek` (tfvars, 0,70 kr ex VAT per part); **Change** next to the SMS price on the Billing tab sets `billing.smsPriceSek` for one customer. A part is 160 GSM-7 characters, 70 when the text has other characters (emoji), long messages in parts of 153 / 67 (`application/shared/sms.py`). Parts are counted when sent, per customer, location and type (`smsParts`, `smsBooking`, `smsReminder`, `smsOrder`, `smsCatering` on the DAY and LOC rows); SMS sent before the deploy that counts parts are not charged. |
| Plans and prices | `var.plans` (tfvars): `price_sek` per month excluding VAT on the `PLAN#` rows. `payments/billing` still creates the Swedish VAT rate (`Moms`, 25 %, exclusive; `BILLING_TAX_RATE_ID`) and one Stripe product and price per plan as a catalog reference; the invoice lines are plain amounts, so a changed `price_sek` needs nothing in Stripe; like any price change it applies from the next period (see Plan change). |
| Own price | The form and the Plan tab take a monthly price (SEK ex VAT), stored as `billing.priceSek`. |
| Terms | `billing.terms`: **try-out** (default on the form) can leave at the end of any period and becomes a subscription by itself after `billing_trial_months` (6) counted from the agreement's start date, or with **Convert to subscription**; **subscription**: `billing_notice_months` (3) months' notice. Stored with `termsSince`; the daily task does the conversion. |
| Cancellation | Billing tab, **Cancel agreement**: `endsAt` = the end of the current period (try-out) or the end of the period `billing_notice_months` later (subscription). The customer is invoiced up to `endsAt` on the next run (the final invoice); a try-out leaving mid-period pays the whole period. "Offboard the customer automatically" (default on, `billing.offboardAtEnd`) makes the daily task offboard them once that invoice exists. **Keep the agreement** undoes it. Offboarding from the Danger zone ends the agreement today; the days used are invoiced on the next run. |
| Collection | `send_invoice` (default): Stripe emails the invoice on the 25th, due `billing_days_until_due` (30) days later; paid by card on the hosted invoice page, or by bankgiro to your own account, in which case you mark the invoice paid in Stripe (`paid_out_of_band`). `charge_automatically`: the card on file (a **card link**, Stripe Checkout in setup mode, then **Charge the card**) is charged on the 25th; a failed charge leaves the invoice open for the dunning task. Stripe's own bank transfers do not support SEK. |
| Plan change | `PUT .../plan` (with the optional own price) and a changed SMS price apply from the next period: `billing.priceHistory` ([{from, monthlySek, planName, smsPriceSek}], written at the start and on every change, pruned by the run) keeps the prices the running period began with, and the invoice uses those. Two changes on one day: the last one counts (a price fixed on the start day is the start price). The daily dunning task records prices changed outside the console (a changed `price_sek` or `sms_price_sek` in tfvars) the same way, and gives agreements from before price history theirs. Extra-location overrides are not priced. |
| Suspend / resume | Leave the agreement alone: a suspended customer still owes and is still invoiced. |
| Unpaid invoice | The daily **dunning task** (platform-tenants, `{"financeTask": "dunning"}`, `billing_dunning_schedule`) works every open invoice through Stripe: **reminders** from the day after the due date and every `billing_reminder_interval_days` (7) days, as Stripe re-sends of the invoice email (`POST /invoices/{id}/send`; card-charged invoices are left to Smart Retries); the **late fee** `billing_late_fee_sek` (450 kr, VAT-free, förseningsavgift) once per invoice still unpaid `billing_late_fee_after_days` (7) days after the due date, as an invoice item that lands on the customer's next invoice; **interest** (dröjsmålsränta) when a late invoice is paid: the overdue amount at `billing_reference_rate_pct` + `billing_interest_margin_pct` (8) per year for the days late, as a VAT-free invoice item; a customer whose agreement has ended gets a one-off invoice for the items at once. Every step is recorded on the ledger row (`remindersSent`, `lastReminderAt`, `lateFeeAdded`, `interestAdded`), so a re-run never repeats it. Past due is the older of `billing.pastDueSince` (set by `invoice.payment_failed`, a card) and the oldest open invoice past its due date in the ledger (an emailed invoice, which never fails a payment); customers past due longer than `billing_suspend_after_days` (14; 0 = never) are suspended exactly like Suspend in the console and resumed when nothing is overdue any more. Before reminding about or charging a fee on an overdue invoice the task reads it from Stripe, so an invoice paid while its webhook was missed is booked as paid instead. The operators get one email per run that did something. **Payments** on the Finance page shows who has paid for a month, with days late, reminders and fees, a Send reminder button and **Run invoicing** (a preview of every invoice the run would create, then the run). |
| First version | A customer still on a Stripe subscription from the first version (billed in advance, `billing.legacySubscriptionId` afterwards): the first run cancels the subscription without a final invoice, voids its open advance invoice and continues in arrears from the same start date (`migrated` in the run result). |

### Webhook (`platform-stripe-webhook`, path `/billing`)

The platform billing endpoint (`payments/stripe`, `platform_billing_events`):

| Event | Effect |
|---|---|
| `invoice.finalized`, `invoice.paid`, `invoice.payment_failed`, `invoice.voided`, `invoice.marked_uncollectible` | finance table: the invoice row (`INVOICE#<created day>#<in_...>`, with the period and the fee / SMS split from the lines) and the day's `invoicedSek` (finalized), `paidSek` (paid), reversal (voided); `lastPaidAt`, `lastPaymentFailedAt` and `pastDueSince` (set on a failed payment, cleared when paid) on the profile |
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
| `TENANT#<id>` | `DAY#<yyyy-mm-dd>` | finance-rollup (`requests`, `bookings`, `orders`, `costSek`, `costSplitSek`, `mrrSek` from the agreement, `smsRevenueSek` = `smsParts` x the customer's SMS price, `planId`, `active`); senders (`emails`, `sms`, `marketingEmails`, `smsParts`, `smsBooking`, `smsReminder`, `smsOrder`, `smsCatering`, ADD); webhook / Stripe import (`invoicedSek`, `paidSek`, `creditedSek`, ADD) | one row per customer and day |
| `TENANT#<id>` | `LOC#<locationId>#DAY#<yyyy-mm-dd>` | finance-rollup (`requests`, `bookings`, `orders`, `costSek`: the location's share of the customer's cost, by requests, else bookings and orders, else equally; `smsRevenueSek`); senders (`emails`, `sms`, `smsParts` and the per-type counters, ADD) | one row per location and day; the Finance page's location filter (revenue stays the customer's) and the per-location split on the SMS invoice line |
| `TENANT#<id>` | `INVOICE#<day>#<in_...>` | webhook, Stripe import | status, amounts ex and incl VAT, dates, links, booking flags, `periodStart` / `periodEnd`, `feeSek`, `smsParts`, `smsSek` |
| `TENANT#<id>` | `CREDIT#<day>#<cn_...>` | webhook | credit notes |
| `PLATFORM` | `COST#<day>` | finance-rollup | USD by service, rate, SEK |
| `PLATFORM` | `DAY#<day>` | finance-rollup | customers active / new / churned, MRR, cost, usage (incl. `smsParts`), `smsRevenueSek` and revenue totals |
| `PLATFORM` | `JOB#latest`, `JOB#<time>` | finance-rollup | last run, days done, warnings |

Day is the grain: week, month, quarter, year and any range are sums over
`DAY#` rows (one Query per customer). MRR on the Finance page is the
agreement's monthly price from `PROFILE.billing` (own price or the plan's),
not a Stripe figure; the `mrrSek` on day rows is the snapshot behind the
MRR trend chart. The SMS tile and column show the parts charged, what
they bring in (`smsRevenueSek`) and the SNS cost share behind them.

## 4. Jobs and schedules

| What | Where | When |
|---|---|---|
| finance-rollup | `compute/lambda/finance-rollup`, role `security/iam/finance-rollup`, code `application/functions/finance-rollup` | `finance_rollup_schedule` (04:30 UTC). Also `{"from","to"}` from Booqy Console's **Rebuild** (max 92 days, yesterday at the latest) and self-continuation near its timeout |
| invoicing | platform-tenants `{"financeTask": "invoice"}`, same role | `billing_invoicing_schedule` (the 25th, 05:00 UTC): one invoice per customer for the period that ended on the 24th (monthly price pro rata plus the SMS line), card charges, first-version migration. Also by hand: **Run invoicing** on the Payments view (`POST /platform/finance/invoicing`, `dryRun` for the preview) and **Invoice now** on a customer's Billing tab (`POST .../billing/invoice`) |
| dunning | platform-tenants `{"financeTask": "dunning"}`, role `security/iam/scheduler-invoke-platform-tenants` | `billing_dunning_schedule` (05:00 UTC): reminders, late fee, interest, past-due suspension and resumption, try-out conversion after `billing_trial_months`, offboarding of ended agreements once their final invoice exists |
| webhook | platform-stripe-webhook `/billing` | on every Stripe event |
| Stripe import | Booqy Console, Finance page, **Import from Stripe** (`POST /platform/finance/stripe-sync`) | by hand: re-reads every customer's invoices (missed webhooks) |

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
  (new): EventBridge Scheduler roles for the schedules (the invoicing
  schedule reuses the platform-tenants one).
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
reference rate (1 January and 1 July). The contract should also state
that the monthly price is invoiced in arrears for the period from the
25th to the 24th, pro rata for a part period, and that SMS are charged
per part at `sms_price_sek` (0,70 kr ex VAT) unless agreed otherwise.

## 6. Hand set-up (Terraform cannot)

Stripe Dashboard, once per mode (sandbox and live):

- Billing → Settings → **Subscriptions and emails** (the invoice email
  settings apply to one-off invoices too): send finalized invoices and
  receipts to customers, reminders before and after the due date, Smart
  Retries for card payments, and what happens when retries fail (leave
  the invoice open; the dunning task here suspends the customer after
  `billing_suspend_after_days`).
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
