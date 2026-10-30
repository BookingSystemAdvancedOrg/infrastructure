# Catering: request → offer → both parties sign → payment / invoice

The contract between this repo's catering resources and the application
code. Infra decides *where* each step runs and what it may touch; this
document is what the handlers must implement for that to hold.

## Decisions this design is built on

- Customers are private (B2C) **and** companies (B2B); no customer account -
  access is a magic link.
- The owner can adjust an offer freely; every save is a new, immutable
  offer version. The customer signs **one specific version**.
- **Prices come only from the server** (issue 5): `POST …/catering/quote`
  (catering-requests) prices packages x guests, dishes x portions, the tier
  discount by guests, the delivery band from the road distance (Amazon
  Location v2: `geo-places` Geocode + `geo-routes` CalculateRoutes, IAM auth,
  single-use results, nothing stored but the distance), the cleaning fee and
  the VAT per line. The calculator only shows that answer, as an estimate.
  An address that can't be located still gives a request, with the delivery
  fee left to the restaurant (`deliveryFeeManual`); beyond the last band
  there is no delivery. A request is priced again the same way and keeps the
  snapshot (lines with `vatRate`, `distanceKm`, `ruleRefs`).
- **VAT per line** (C5): `serviceIncluded` per offer (default from
  `defaultServiceIncluded`); with service 12 %, food only by the takeaway
  rule (6 % 2026-04-01 to 2027-12-31, else 12 %); delivery and cleaning
  follow the food. Stripe gets the account's tax rate for that percentage.
- **Both parties sign the offer PDF** (C2): catering-document renders each
  sent version (WeasyPrint, PDF/A-3b); its SHA-256 is what is signed. The
  **restaurant signs first** in admin, only then is the guest told and may
  sign. The provider is behind `shared/signing.py` (secret
  `catering/signing-provider`, field `provider`): `simulator` in dev and
  `bankid_direct` (BankID RP API v6, `shared/bankid.py`) and **`scrive`**,
  the chosen provider (2026-10-28, `shared/signing_scrive.py`, Document
  API v2): one Scrive document per offer version, the restaurant
  (sign_order 1) then the guest (2), both with `se_bankid` on Scrive's
  page, Scrive sends no e-mails of its own, the sealed PDF goes into the
  locked package. A start answers either
  `kind: bankid` (QR / app, polled through `…/status`) or `kind: redirect`
  (the provider's page, back with `?signering=klar`).
- **Simple acceptance** without BankID (C8), off by default per restaurant
  (`allowSimpleAcceptance`): name, and for a company role + authority;
  stored as locked evidence like a signature. Companies give the signatory
  (name, role, authority) already in the request.
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
                 │  ▲
                 ▼  │ owner sends vN+1
           change_requested (guest asked for changes)        offer_sent ─► rejected (guest declined)
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
an `AUDIT#` entry in catering-request-history - in one
`TransactWriteItems` when capacity is involved.

| Transition | Written by | Trigger |
|---|---|---|
| → requested | catering-requests | `POST …/catering/requests` (Turnstile-verified) |
| requested (+ `reviewedAt`, "Under granskning") | catering-offer | first `PUT …/offer` (draft) |
| requested → offer_sent, offer_sent → offer_sent (new version) | catering-offer | `POST …/offer/send` (PDF + signing order; the previous order is cancelled) |
| offer_sent (+ `restaurantSignedAt`, notice to the guest) | catering-offer | `POST …/restaurant-sign` + `…/status` |
| requested → declined | catering-offer | `POST …/decline` |
| requested → expired | catering-lifecycle | timer `request-expiry` |
| offer_sent → signed | catering-customer / catering-signing-webhook | the guest's signature (`…/customer/sign/status`, `…/customer/accept`) or a provider callback; a company is then invoiced by catering-lifecycle (→ confirmed) |
| offer_sent / signed → expired | catering-lifecycle | timer `offer-expiry` (at validUntil) |
| signed → confirmed | catering-stripe-webhook | `checkout.session.completed` (paid) / `async_payment_succeeded` |
| confirmed → delivered | catering-offer | `POST …/delivered` |
| delivered → closed | catering-offer / catering-stripe-webhook | whichever of "delivered" and "paid" happens last |
| confirmed → cancelled_by_restaurant | catering-offer | `POST …/cancel` (refund or credit note) |

## Data layout

**catering-requests** (PK `LOCATION#<locationId>`)

- `REQUEST#<requestId>` - head item: `status`, `version`, `customerType`
  (`private`/`company`), contact + company fields, `deliveryDate`,
  `fulfilment` (`pickup`/`delivery`), `equipmentReturn` (`cleaned`/
  `not_cleaned`, the latest sent offer's once one is sent), `priceSnapshot`,
  `currentOfferVersion`, `validUntil`, `linkVersion`, `signedOfferVersion`,
  `signedDocHash`, `stripeCheckoutSessionId`, `stripeInvoiceId`,
  `invoiceNumber`, `invoiceStatus`, `guests`, `signatory`, `serviceIncluded`,
  `reviewedAt`, `restaurantSignedAt`, `signedPdfKey` and `signing` for the
  version being signed: `{offerVersion, pdfKey, pdfSha256, order (the
  provider's signing order, shared/signing.py), signatures {restaurant,
  customer}}`. A new version replaces it (the old order is cancelled).
- `CAPACITY#<yyyy-mm-dd>` - `heldServings`; reserve with
  `ADD heldServings :n` + condition `heldServings + :n <= maxServingsPerDay`.

**catering-request-history** (PK `REQUEST#<requestId>`, append-only -
always `PutItem` with `attribute_not_exists(SK)`)

- `OFFER#v0001` - line items with `vatRate`, `serviceIncluded`, delivery
  fee, terms text, `validUntil`, `pdfKey`, `pdfSha256`, `equipmentReturn` and
  `totals.cleaningFee` (öre). The cleaning fee is copied from
  `cateringSettings.cleaningFee` (kronor, owner can change it any time) into
  the request and each version, and is part of the signed document, so a
  signed version keeps its price. Same 12 % VAT as the food, not discounted;
  Stripe Checkout and the invoice get it as its own line.
- `AUDIT#<ISO ts>#<seq>` - actor, action, from/to status, IP, user agent,
  document hash. Webhook-driven entries use `AUDIT#STRIPE#<evt id>` /
  `AUDIT#SIGNING#<event id>` instead, which doubles as the dedup key.

**Webhook deduplication** - no separate table. Each webhook handler first
writes its audit entry as `AUDIT#STRIPE#<evt id>` / `AUDIT#SIGNING#<event id>`
in catering-request-history with `attribute_not_exists(SK)`; on
`ConditionalCheckFailed` (a redelivery), return 200 and stop. Status updates
stay conditional on `status` + `version` as a second guard.

**catering-menu** (PK `LOCATION#<locationId>`) - the restaurant's own
catering menu, separate from the regular menu (`MENU#` items are never
changed by catering). `DISH#<dishId>`: `name`, `description`,
`pricePerPortion` (kronor incl. VAT, like menu prices), `allergens[]`,
`dietary[]`, `active`, `sort`, `version`, optional `sourceMenuItemId` (copied
with "Hämta från menyn", no link). `PACKAGE#<packageId>`: `name`,
`description`, `pricePerGuest` (kronor), `dishIds[]`, optional `minGuests`,
`active`, `sort`, `version`. Written by catering-settings (owner, conditional
on `version`); read by catering-requests and catering-offer.

**catering-documents** (S3, Object Lock enabled, **no default retention**, C7):

| Key | Written by | Retention |
|---|---|---|
| `<tenantId>/offers/<requestId>/v<NNNN>.pdf` | catering-document | tagged `retention=offer`, expires after 13 months (lifecycle); the signed S3 version is pinned (`signing.pdfVersionId`) |
| `<tenantId>/offers/<requestId>/v<NNNN>-restaurant-bankid.json` | catering-offer | the restaurant's evidence while the contract is not yet binding: unlocked, tagged `retention=offer`, expires with the offer |
| `<tenantId>/signed/<requestId>/v<NNNN>/` `restaurant-<bankid\|scrive>.json` (copied in), `customer-<bankid\|scrive>.json` or `customer-acceptance.json`, `offer.pdf`, `scrive-sealed.pdf` (Scrive's sealed copy with its evidence attachments; `manifest-sealed.json` when it came later), `manifest.json` (SHA-256 of every file), written when the customer signs | catering-customer, catering-signing-webhook | per object: prod COMPLIANCE 7 years rounded up to 31 December of that year (Bokföringslagen), dev GOVERNANCE 1 day (`DOCUMENT_LOCK_MODE` / `DOCUMENT_LOCK_DAYS` / `DOCUMENT_LOCK_YEAR_END`, `s3:PutObjectRetention`) |
| `<tenantId>/invoices/<stripeInvoiceId>.pdf` | nothing yet: Stripe hosts the invoices; a writer must set the same per-object lock | same as signed/ |

Never hand out object URLs - presigned GET only (`…/documents/{offer|signed|signature}`).

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
| `sign-reminder-<requestId>` | restaurant signed (offer_sent) | 10:00 local, `signReminderDaysBefore` days before validUntil | guest reminder (e-mail + SMS) if not signed |
| `day-before-<requestId>` | → confirmed | 10:00 local the day before deliveryDate (`dayBeforeReminder`) | guest reminder (e-mail) |

`owner-reminder` fires `ownerReminderHours` after the request (0 = off) and
reminds the owner (e-mail + SMS) while it is still `requested`. Reminders
set a notice (`catering_owner_reminder`, `catering_sign_reminder`,
`catering_day_before`); a reminder time already passed is skipped. Local
times use the location's time zone (zoneinfo, DST-safe). Leaving
`requested` deletes the first two; leaving `offer_sent`/`signed` for
`confirmed` deletes `offer-expiry`, leaving `offer_sent` deletes
`sign-reminder`, a cancellation deletes `day-before`. A timer that fires on
a request no longer in the expected status is a no-op.

## Signing webhook

`POST /webhooks/signing/catering?l=<locationId>&r=<requestId>&t=<token>`
(catering-signing-webhook), the URL set per signing order. The request's
current order must verify the callback (`verify_webhook`: the order's own
random token, constant time, or the provider's signature) or it answers 401;
an event already in the history (`AUDIT#SIGNING#<eventId>`) answers 200; the
state is always read again from the provider (`status`) and each party that
signed there is recorded with its evidence, conditionally on status +
version; then the event is written. A failure answers 503 and logs
`SIGNING_WEBHOOK_FAILED` (alarm `catering-signing-webhook-failed`, plus a
Lambda Errors alarm) so the provider retries.

Scrive's callbacks are unsigned: only the `t` token counts, the form body
(`document_id`, `document_json`) only names the event (its hash) and a
callback about another document is refused. Scrive seals the PDF after the
last signature; until it is ready the request is `signed` with
`signing.sealPending` and the webhook answers 503 `seal_pending` (no audit
entry, so Scrive's retry is processed), alarming only after 30 minutes.
If Scrive gave up retrying, trigger the callback again from Scrive (API
`POST /api/v2/documents/<documentId>/callback`, the id is
`signing.order.documentId` on the request). `signed` downloads the sealed
PDF (`sealedPdfKey`) once it is there, else our locked copy.

Alarms: `catering-signing-unavailable` (Scrive down or credentials refused:
`SIGNING_UNAVAILABLE` in catering-offer or catering-customer) and
`<fn>-errors` for catering-offer, -customer, -document, -lifecycle and
-stripe-webhook (catering.tf).

## Abuse limits

Per IP / phone / e-mail on requests, per IP on quotes (120 per 10 min,
plus a route throttle); Amazon Location lookups per IP (20 per 10 min, 429)
and per location (500 a day, then the quote leaves the delivery fee to the
restaurant). The restaurant's origin is geocoded once on settings save
(IntendedUse Storage, `cateringOrigin` on the location) and distances per
address are cached in the Lambda for 15 minutes, so changing quantities
costs no lookups.
per request and per IP on signing starts and acceptances (10 / 20 per hour,
each BankID order costs money), all in `shared/request_guard.py`.

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
(`dlq_replay_interval_minutes`: 6 in dev, 720 in production) and redelivers each
item to the Lambda that owns it - scheduled invocations to the function in
the record (allow-listed), stream pointers by re-reading the records
(possible for ~24h). A message is deleted only after the owning Lambda
succeeded; after 3 failed replays it is escalated to the `platform-alerts`
SNS topic once and parked. Code: `functions/dlq-replay/app.py` in the
application repo.

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
