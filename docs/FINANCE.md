# Finance: invoicing in advance and the Finance page

What every customer pays and what they cost, per day, and how Booqy
Console shows it. Code: `payments/billing` (Stripe VAT rate and plan catalog),
`storage/dynamodb/finance` (the table), `compute/lambda/finance-rollup`
(the nightly job, code in the application repo), platform-stripe-webhook
(`/billing` events, application repo), platform-tenants (console API,
booqy-console repo: `billing.py`, `finance.py`).

## 1. The agreement: one invoice per month, in advance

Every restaurant company (tenant) is a **Stripe Customer** on YOUR
platform account. There is no Stripe subscription: the platform keeps the
agreement itself (`PROFILE.billing`) and builds one Stripe invoice per
calendar month, on the 1st, in advance, from its own figures. This has
nothing to do with the restaurant's Connect account
(guest payments), which stays as it is.

| Piece | Where |
|---|---|
| Billing period | The calendar month (Europe/Stockholm), **in advance** (owner 2026-11-14). The **invoicing run** (`billing_invoicing_schedule`, daily 05:30 UTC, platform-tenants `{"financeTask": "invoice"}`, after finance-rollup and dunning) invoices on the 1st the month that starts; on an agreement's first day (a start, or the first paid day after Free) the rest of that month at once, pro rata by the days of the month; an end date inside a month is pro rata too. Any other day only catches up (a failed or unfinished run). `billing.paidThrough` is the last day invoiced, `billing.pricedThrough` the last day invoiced at a price (days paid at a price are never invoiced again). A run stops starting restaurants 30 s before the Lambda timeout and lists them as "not reached"; the alarm `platform-tenants-errors` emails the operators when a run crashes. Helpers `period_of`, `month_end`, `pending_advance`, `fee_for` in the console API's `billing.py`. |
| Agreement | `PROFILE.billing`: `status` active \| ended, `startsAt`, `endsAt`, `terms` trial \| subscription with `termsSince`, `priceSek` (the customer's own monthly price), `collectionPreference` card \| invoice, `cycle` advance, `paidThrough`, `offboardAtEnd`, `customerId`, the card (`defaultPaymentMethod`, `cardBrand`, `cardLast4`, written by the webhook). Started from the **New customer** form or the **Billing** tab; the console creates the Stripe customer on the PLATFORM account (never the restaurant's connected account) and claims `STRIPE_CUSTOMER#<cus> / TENANT`. The customer's legal name, address, billing email (`billingEmail`, else the owner's, else the connected account's) and VAT number (`vatNumber`, else SE + org number + 01, `eu_vat`) are filled from the tenant record and, where it has gaps, the connected Stripe account (company name and address), and kept in step every day (`sync_customer`, only when they changed); `preferred_locales` sv. |
| The invoice | A draft `POST /invoices` with `pending_invoice_items_behavior=exclude` and only its own fee lines (`invoice=<id>` on each item: one per calendar month, a closing invoice can have two), finalized with `auto_advance` (Stripe Smart Retries for a card), then sent or paid. Idempotency keys on every write (`inv-advance-<tenant>-<periodStart>`, `fee-...`, `finalize-<in>`, `send-<in>`, `pay-<in>`). A rerun after Stripe's 24-hour window finds the invoice by `metadata.kind` + `periodStart` and adds only the lines a draft lacks. **Compliance** (mervärdesskattelagen 17 kap 24 §): Stripe's sequential number, issue and due dates, the buyer's name, address and VAT number, the period on every line, net, 25 % VAT and total in SEK; Booqy's org number, registered office and F-skatt as custom fields, name, address and VAT number in the footer and as an account tax id, all from `billing_seller` (`BILLING_SELLER_JSON`, not secret). Prod refuses to invoice without them. A month with nothing to pay (Free) gets no invoice. |
| SMS | Included in the monthly price, never invoiced (the per-part price, `sms_price_sek` and `billing.smsPriceSek`, were removed on 2026-11-14). They are still counted, as our cost: a part is 160 GSM-7 characters, 70 when the text has other characters (emoji), long messages in parts of 153 / 67 (`application/shared/sms.py`). Parts are counted when sent, per customer, location and type (`smsParts`, `smsBooking`, `smsReminder`, `smsOrder`, `smsCatering` on the DAY and LOC rows), and the SNS cost is split by them; the Finance page shows the parts sent and that cost. The SMS-pumping guards and sending limits are unchanged. |
| Free plan | `planId` "free", set on the Plan tab or the New customer form: no monthly charge, Growth's features and limits (derived from `PLAN#growth` on every read, so not in `var.plans`; "free" is reserved there). `billing.freeUntil` = the last free day (default three months from the start, Europe/Stockholm; none = no end date), `freeThenPlanId` (default starter), `freeSince`, `freeNoticeFor`. The daily dunning run: 14 days before the first paid day the owner gets a Swedish email (the console's mail template, the no-reply SES sender) and the operators a line in the dunning summary, once per end date (claimed with a condition, retried the next day if SES fails); the day after the last free day the customer moves to `freeThenPlanId` (conditioned on still being on that free period, so a re-run never switches twice) and, if no agreement runs, one is started from that day. Moving onto or off Free is an `exact` price change: it applies from its own day, pro rata, not from the next period. MRR counts Free as 0. |
| Plans and prices | `var.plans` (tfvars): `price_sek` per month excluding VAT on the `PLAN#` rows. `payments/billing` still creates the Swedish VAT rate (`Moms`, 25 %, exclusive; `BILLING_TAX_RATE_ID`) and one Stripe product and price per plan as a catalog reference; the invoice lines are plain amounts, so a changed `price_sek` needs nothing in Stripe; like any price change it applies from the next period (see Plan change). |
| Own price | The form and the Plan tab take a monthly price (SEK ex VAT), stored as `billing.priceSek`. |
| Terms | `billing.terms`: **try-out** can leave at the end of any month and becomes a subscription by itself after `billing_trial_months` (6), or with **Convert to subscription**; **subscription**: `billing_notice_months` (3) months' notice after the current month. The restaurant accepts **Allmänna villkor för restauranger** in Booqy Admin (Avtal, next to the DPA; `TERMS#<tenant>` rows, `terms` on the profile); booqy.se/villkor has the same payment terms. |
| Cancellation | **Cancel agreement**: `endsAt` = the end of the current month (try-out) or the end of the month `billing_notice_months` later (subscription). Months are invoiced in advance, so cancel now / offboarding today leaves the rest of the paid month unrefunded (the terms say so; a credit note is the operator's choice in Stripe). The agreement becomes ended the day after `endsAt`; "Offboard the customer automatically" then offboards it. |
| Collection | `collectionPreference` **card** (default): the restaurant's owner adds a card in Booqy Admin (Inställningar, Abonnemang, **Lägg till kort**: Stripe Checkout in setup mode, `POST /tenant/billing/card-session`), or the operator sends the console's card link; the webhook makes it the default and every invoice is charged automatically. Until a card exists the invoice is emailed, due in `billing_days_until_due_no_card` (10) days, and admin asks for a card. **invoice** (chosen per customer in the console): emailed, due in `billing_days_until_due` (30) days. |
| Plan change | `PUT .../plan` (with the optional own price) applies from the next period: `billing.priceHistory` ([{from, monthlySek, planName, exact?}], written at the start and on every change, pruned by the run) keeps the prices the running period began with, and the invoice uses those. Two changes on one day: the last one counts (a price fixed on the start day is the start price). The daily dunning task records prices changed outside the console (a changed `price_sek` in tfvars) the same way, and gives agreements from before price history theirs. Extra-location overrides are not priced. Onto or off Free (`exact`) applies from that day, the days before and after it pro rata. |
| Suspend / resume | Leave the agreement alone: a suspended customer still owes and is still invoiced. |
| Unpaid invoice | The daily **dunning task** works every open invoice (asking Stripe first, so a payment whose webhook was missed is booked instead): at `billing_reminder_steps` (3, 7, 14) days after the due date and the final notice at `billing_final_notice_days` (30), the restaurant gets a Swedish reminder email with the payment link (card invoices too) and **the operators get the same step** through the alerts topic (restaurant, invoice number, amount, due date, days overdue, link to the customer in the console), each claimed on the ledger row (`customerReminder<step>At`, `opsReminder<step>At`) so nobody gets the same step twice; a run that was down sends only the newest step. Fees go on separate VAT-free fee invoices (`kind` fees, emailed, 10 days): the **påminnelseavgift** `billing_reminder_fee_sek` (60 kr, agreed in the terms) with the first reminder, the **förseningsersättning** (4 a § lagen 1981:739) `billing_late_fee_sek` (450 kr) less the reminder fee at `billing_late_fee_after_days` (7), once per invoice; **dröjsmålsränta** (räntelagen 6 §, `billing_reference_rate_pct` + 8 per year for the days late) once a late invoice is paid. The operators also get a **daily overdue summary** (only when something is overdue, once a day: `PLATFORM#BILLING / OPS_OVERDUE#<day>`), and the webhook emails them at once when a card payment fails. Nothing is suspended automatically (`billing_suspend_after_days` 0); the console shows overdue customers (list chip, customer page badge, Payments overdue first). |
| Switch from arrears | Agreements on the old cycle (25th to 24th in arrears, `lastInvoicedPeriodEnd`) get one **closing invoice** (`kind` closing) from the day after their last invoiced period to the end of the current month, one line per month, then continue in advance from the next 1st: no gap, no overlap. Never invoiced: straight to advance. One-shot `{"financeTask": "migrate_to_advance"}` (dry run by default, `"dryRun": false` to run); the daily run does the same. A Stripe subscription from the first version is cancelled and its open invoice voided first. |

### Webhook (`platform-stripe-webhook`, path `/billing`)

The platform billing endpoint (`payments/stripe`, `platform_billing_events`):

| Event | Effect |
|---|---|
| `invoice.finalized`, `invoice.paid`, `invoice.payment_failed`, `invoice.sent`, `invoice.voided`, `invoice.marked_uncollectible` | finance table: the invoice row (`INVOICE#<created day>#<in_...>`, with `kind` and the period) and the day's `invoicedSek` (finalized), `paidSek` (paid), reversal (voided); `lastPaidAt`, `lastPaymentFailedAt`, `pastDueInvoices` and `pastDueSince` (set on a failed payment, cleared when the last failed invoice is paid) on the profile |
| `invoice.payment_failed`, `invoice.payment_action_required` | an immediate email to the operators (alerts topic), once per invoice and attempt (`opsAlert<step>At` on the ledger row) |
| `checkout.session.completed` (setup), `payment_method.attached` | the card becomes the customer's default for invoices (`default-pm-<id>` key) |
| `customer.updated` | the default card (id, brand, last four) on `PROFILE.billing` |
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
| `TENANT#<id>` | `DAY#<yyyy-mm-dd>` | finance-rollup (`requests`, `bookings`, `orders`, `costSek`, `costSplitSek`, `mrrSek` from the agreement (0 on Free), `planId`, `active`; an `smsRevenueSek` from before 2026-11-14 is removed when a day is recomputed); senders (`emails`, `sms`, `marketingEmails`, `smsParts`, `smsBooking`, `smsReminder`, `smsOrder`, `smsCatering`, ADD); webhook / Stripe import (`invoicedSek`, `paidSek`, `creditedSek`, ADD) | one row per customer and day |
| `TENANT#<id>` | `LOC#<locationId>#DAY#<yyyy-mm-dd>` | finance-rollup (`requests`, `bookings`, `orders`, `costSek`: the location's share of the customer's cost, by requests, else bookings and orders, else equally); senders (`emails`, `sms`, `smsParts` and the per-type counters, ADD) | one row per location and day; the Finance page's location filter (revenue stays the customer's) |
| `TENANT#<id>` | `INVOICE#<day>#<in_...>` | webhook, Stripe import | status, amounts ex and incl VAT, dates, links, booking flags, `periodStart` / `periodEnd`, `feeSek` (`smsParts`, `smsSek` on invoices from before 2026-11-14) |
| `TENANT#<id>` | `CREDIT#<day>#<cn_...>` | webhook | credit notes |
| `PLATFORM` | `COST#<day>` | finance-rollup | USD by service, rate, SEK |
| `PLATFORM` | `DAY#<day>` | finance-rollup | customers active / new / churned, MRR, cost, usage (incl. `smsParts`) and revenue totals |
| `PLATFORM` | `JOB#latest`, `JOB#<time>` | finance-rollup | last run, days done, warnings |

Day is the grain: week, month, quarter, year and any range are sums over
`DAY#` rows (one Query per customer). MRR on the Finance page is the
agreement's monthly price from `PROFILE.billing` (own price or the plan's),
not a Stripe figure; the `mrrSek` on day rows is the snapshot behind the
MRR trend chart; Free customers count 0. The SMS tile and column show
the parts sent and the SNS cost share behind them (SMS are included in
the price: no SMS revenue).

## 4. Jobs and schedules

| What | Where | When |
|---|---|---|
| finance-rollup | `compute/lambda/finance-rollup`, role `security/iam/finance-rollup`, code `application/functions/finance-rollup` | `finance_rollup_schedule` (04:30 UTC). Also `{"from","to"}` from Booqy Console's **Rebuild** (max 92 days, yesterday at the latest) and self-continuation near its timeout |
| invoicing | platform-tenants `{"financeTask": "invoice"}`, same role | `billing_invoicing_schedule` (daily 05:30 UTC): on the 1st one invoice per customer for that month in advance, on a start day the rest of the month (pro rata; nothing for Free), card charges, the closing invoice of the switch from arrears. Also by hand: **Run invoicing** on the Payments view (`POST /platform/finance/invoicing`, `dryRun` for the preview) and **Invoice now** on a customer's Billing tab (`POST .../billing/invoice`) |
| dunning | platform-tenants `{"financeTask": "dunning"}`, role `security/iam/scheduler-invoke-platform-tenants` | `billing_dunning_schedule` (05:00 UTC): reminders to the restaurant and the operators, the daily overdue summary, fees, interest, the billing customer's details, try-out conversion after `billing_trial_months`, offboarding of ended agreements once their final invoice exists |
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
räntelagen §6); the påminnelseavgift (60 kr) only because the restaurant
terms (Allmänna villkor för restauranger, 2026-11-v1) state it, and only
on invoices created after the restaurant accepted them (2 § lagen
1981:739); without it the förseningsersättning is the full 450 kr, with it
450 kr less the reminder fee. Dröjsmålsränta referensränta + 8 %. Update
`billing_reference_rate_pct` in tfvars when the Riksbank sets a new
reference rate (1 January and 1 July). The terms state that the monthly
price is invoiced in advance on the 1st for that calendar month, pro rata
for a part month, and that SMS are included in the monthly price.

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
