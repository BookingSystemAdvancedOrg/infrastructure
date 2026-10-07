# Catering: request → offer → BankID signature → payment / invoice

The contract between this repo's catering resources and the application
code. Infra decides *where* each step runs and what it may touch; this
document is what the handlers must implement for that to hold.

## Decisions this design is built on

- Customers are private (B2C) **and** companies (B2B); no customer account —
  access is a magic link.
- The owner can adjust an offer freely; every save is a new, immutable
  offer version. The customer signs **one specific version**.
- The customer always signs with **BankID** (through a signing provider).
- **No changes and no cancellation by the customer** after signing. Only the
  restaurant can cancel (illness/force majeure) → refund or credit note.
- Capacity for a date is **checked** at submit and **reserved** when the
  offer is sent; released on decline / expiry / restaurant cancellation.
- B2C pays at signing (Stripe Checkout: Swish/card). If payment fails or the
  session expires, the **signature is kept** and the customer retries from
  the link until the offer's valid-until date.
- B2B is invoiced **at signing** through Stripe Invoicing, due signing +
  N days (N from cateringSettings). Stripe emails invoices and overdue
  reminders; SES (NotificationFn) sends every order-flow email.
- Food and non-alcoholic drinks only; VAT per line item via Stripe tax
  rates - per restaurant, created on its connected account at onboarding
  from `default_tax_rates` and stored in `PROFILE.stripe.taxRates`.

## Status machine (head item `status`, lowercase)

```
requested ─► offer_sent (vN, capacity held) ─► signed ─► confirmed ─► delivered ─► closed
   │              │   ▲ (owner sends vN+1)        │  (B2C paid)  ▲
   │              │   └──────────┘                │              │ B2B: confirmed directly at signing
   ▼              ▼                               ▼              │      + Stripe invoice
declined /     expired                         expired (still unpaid at validUntil)
expired
                         confirmed ─► cancelled_by_restaurant (refund / credit note)
```

`closed` = delivered **and** paid (B2C at confirmation, B2B when the
invoice is paid). Every transition is a conditional `UpdateItem` on
`status` **and** `version` (optimistic lock, `version = version + 1`) plus
an `AUDIT#` entry in catering-request-history — in one
`TransactWriteItems` when capacity is involved.

| Transition | Written by | Trigger |
|---|---|---|
| → requested | catering-requests | `POST …/catering/requests` (Turnstile-verified) |
| requested → offer_sent, offer_sent → offer_sent (new version) | catering-offer | `POST …/offer/send` |
| requested → declined | catering-offer | `POST …/decline` |
| requested → expired | catering-lifecycle | timer `request-expiry` |
| offer_sent → signed (B2C) / confirmed (B2B) | catering-signing-webhook | provider callback |
| offer_sent / signed → expired | catering-lifecycle | timer `offer-expiry` (at validUntil) |
| signed → confirmed | catering-stripe-webhook | `checkout.session.completed` (paid) / `async_payment_succeeded` |
| confirmed → delivered | catering-offer | `POST …/delivered` |
| delivered → closed | catering-offer / catering-stripe-webhook | whichever of "delivered" and "paid" happens last |
| confirmed → cancelled_by_restaurant | catering-offer | `POST …/cancel` (refund or credit note) |

## Data layout

**catering-requests** (PK `LOCATION#<locationId>`)

- `REQUEST#<requestId>` — head item: `status`, `version`, `customerType`
  (`private`/`company`), contact + company fields, `deliveryDate`,
  `fulfilment` (`pickup`/`delivery`), `priceSnapshot`,
  `currentOfferVersion`, `validUntil`, `linkVersion`, `signedOfferVersion`,
  `signedDocHash`, `stripeCheckoutSessionId`, `stripeInvoiceId`,
  `invoiceNumber`, `invoiceStatus`.
- `CAPACITY#<yyyy-mm-dd>` — `heldServings`; reserve with
  `ADD heldServings :n` + condition `heldServings + :n <= maxServingsPerDay`.

**catering-request-history** (PK `REQUEST#<requestId>`, append-only —
always `PutItem` with `attribute_not_exists(SK)`)

- `OFFER#v0001` — line items, VAT per line, delivery fee, terms text,
  `validUntil`, `pdfKey`, `pdfSha256`.
- `AUDIT#<ISO ts>#<seq>` — actor, action, from/to status, IP, user agent,
  document hash. Webhook-driven entries use `AUDIT#STRIPE#<evt id>` /
  `AUDIT#SIGNING#<event id>` instead, which doubles as the dedup key.

**Webhook deduplication** — no separate table. Each webhook handler first
writes its audit entry as `AUDIT#STRIPE#<evt id>` / `AUDIT#SIGNING#<event id>`
in catering-request-history with `attribute_not_exists(SK)`; on
`ConditionalCheckFailed` (a redelivery), return 200 and stop. Status updates
stay conditional on `status` + `version` as a second guard.

**catering-documents** (S3, Object Lock) — `<tenantId>/offers/<requestId>/v<NNNN>.pdf`,
`<tenantId>/signed/<requestId>/v<NNNN>.pdf`, `<tenantId>/invoices/<stripeInvoiceId>.pdf`. Never
hand out object URLs — presigned GET only.

## Magic links

`<site base>/catering/<locationId>/<requestId>#t=<token>` (site base =
`https://<tenant primaryDomain>`, `CUSTOMER_SITE_URL` only as fallback) with
`token = base64url(HMAC-SHA256(key, "<locationId>#<requestId>#<linkVersion>"))`
and the key from `catering/link-signing-key`. The front-end reads the
fragment and sends it as the `x-order-token` header, so it never reaches
access logs. catering-customer recomputes and compares in constant time.
Bump `linkVersion` to revoke a request's links.

## Timers (catering-lifecycle)

Only catering-lifecycle creates or deletes schedules, from the stream
(`SCHEDULE_GROUP_NAME`, target = its own ARN from
`context.invoked_function_arn`, role `SCHEDULER_INVOKE_ROLE_ARN`,
`DeadLetterConfig` = `SCHEDULER_DLQ_ARN`, `ActionAfterCompletion = DELETE`).
Names are deterministic so stream retries are idempotent:

| Schedule name | Created on | Fires at | Action |
|---|---|---|---|
| `owner-reminder-<requestId>` | → requested | submit + reminder hours | remind owner |
| `request-expiry-<requestId>` | → requested | submit + expiry hours | requested → expired |
| `offer-expiry-<requestId>` | → offer_sent (replaced per version) | validUntil | offer_sent/signed → expired, release capacity |
| `day-before-<requestId>` | → confirmed | deliveryDate − 1 day | customer reminder |

Leaving `requested` deletes the first two; leaving `offer_sent`/`signed`
for `confirmed` deletes `offer-expiry`. A timer that fires on a request
no longer in the expected status is a no-op (the conditional update fails).

## Stripe

Every call below runs on the restaurant's connected account
(`stripe_account=<tenant/location account>`, platform key from
`STRIPE_SECRET_ARN`); webhooks arrive as Connect events identified by
`event.account` - see docs/handoff/BACKEND.md §5.

- B2C Checkout: `mode=payment`, `invoice_creation.enabled=true` (receipt in
  the same numbering series), `expires_at` = 30 min, metadata
  `{ locationId, requestId, offerVersion }`, idempotency key
  `checkout-<requestId>-<attempt>`.
- B2B invoice on → confirmed: Customer (org number, invoice address, Peppol
  id later), invoice items from the signed offer version with
  the tenant's `stripe.taxRates`, `collection_method=send_invoice`,
  `days_until_due` from cateringSettings, `custom_fields` org number /
  reference, `footer` Bankgiro + OCR + F-skatt. Idempotency key
  `invoice-<requestId>`.
- Bankgiro payment: owner → `POST …/invoices/{invoiceId}/mark-paid` →
  `invoices.pay(paid_out_of_band=true)`.
- `invoice.finalized` → copy `invoice_pdf` to `invoices/` in the archive.

## Failures: DLQs and the scheduled replay

Covered platform-wide, not just for catering - see `storage/sqs/dead-letter`.

| DLQ | Written by (when) | Message body |
|---|---|---|
| `catering-lifecycle-stream-dlq` | Lambda's stream trigger, after `catering-lifecycle` failed a batch 10× | Pointer to the stream records |
| `notification-stream-dlq` | Lambda's stream triggers on the reservation, order and catering-requests streams, after `notification` failed a batch 5× | Pointer to the stream records |
| `scheduled-invocation-dlq` | Lambda's async on-failure destination of `catering-lifecycle`, `no-show-check`, `reactivate-menu-item`, `expire-layout-version` (after 2 async retries) - configured in Terraform | Invocation record; original input in `requestPayload` |
| `scheduled-invocation-dlq` | EventBridge Scheduler, when it can't reach `catering-lifecycle` at all (`DeadLetterConfig` set by catering-lifecycle's app code) | The schedule's input |

`dlq-replay` drains all three on a recurring schedule
(`dlq_replay_interval_minutes`: 6 in dev, 720 in prod) and redelivers each
item to the Lambda that owns it - scheduled invocations to the function in
the record (allow-listed), stream pointers by re-reading the records
(possible for ~24h). A message is deleted only after the owning Lambda
succeeded; after 3 failed replays it is escalated to the `platform-alerts`
SNS topic once and parked. Reference implementation:
`compute/lambda/dlq-replay/src/handler.py`.

The only DLQ setting in application code: `catering-lifecycle` passes
`DeadLetterConfig = {"Arn": SCHEDULER_DLQ_ARN}` on every schedule it creates.
Every handler must raise on real failures (or return `batchItemFailures`)
instead of logging and returning success - otherwise nothing is retried
and nothing reaches a DLQ.

Contract this puts on `catering-lifecycle`: besides stream events and timer
payloads it must accept `{"action": "reconcile", "source": "dlq-replay",
"window": {...}}` - sent when failed stream records have already expired -
and re-check every open request (`requested`, `offer_sent`, `signed`,
`confirmed`) from the table: timers present, company invoice issued,
expiries applied. It already has the table access for this.

CloudWatch alarms (to the same topic) cover the replay not doing its job: a
DLQ message older than two replay intervals, or the replay Lambda erroring.
