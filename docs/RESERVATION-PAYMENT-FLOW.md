# Reservation payments: card-on-file via SetupIntent

## Why cards only (and why Swish/Klarna are orders-only)

A reservation charges **0 kr at booking** but may charge a fee later
(late cancel / no-show) with **no customer present**. That is a
merchant-initiated, off-session charge, and only cards support it:

- **Swish** is a push payment - the customer approves each transfer in the
  app at that moment. There is no "save Swish for later" and no
  merchant-initiated pull. A no-show cannot approve their own fee.
- **Klarna** underwrites credit per purchase at a known amount. An
  open-ended "maybe X kr in two weeks" charge can be declined by Klarna's
  risk engine exactly when needed, and disputes on "a purchase I never
  made" skew against the merchant.
- **Cards** authenticate once up front (3DS via SetupIntent) and can then
  be charged off-session with the liability story intact - the model every
  hotel/restaurant no-show system uses.

Orders (pay-now, known amount) take card + Swish + Klarna via Checkout.
Reservations take **card only**, via a Checkout Session in `mode: "setup"`.

## Flow, mapped to the reservation table's status enum

```
1. Customer books
   create-pending-reservation:
     PutItem  status = "pending"
     Create Checkout Session:
       mode                 = "setup"          (0 kr - collects a card, charges nothing)
       currency             = "sek"
       payment_method_types = ["card"]
       metadata             = { locationId, date, reservationId }  (also on setup_intent)
     303 redirect to Stripe

2. Card saved (3DS happens here, while the customer is present)
   webhook: setup_intent.succeeded
     UpdateItem (condition: status = "pending"):
       status                -> "reserved"
       stripeCustomerId      = setup_intent.customer
       stripePaymentMethodId = setup_intent.payment_method
     -> DynamoDB stream fires the existing pending->reserved SMS filter
     -> stripe-webhook schedules no-show-check (existing EventBridge
        Scheduler pattern)

   webhook: setup_intent.setup_failed
     -> reservation stays "pending"; expire it the same way an unpaid
        pending reservation expires today (ttl / cleanup)

3a. Cancelled in time
    cancel-reservation: status -> "cancelled_no_charge". Nothing charged.

3b. Late cancel / no-show (no-show-check fires, or staff action)
    Create off-session PaymentIntent:
      amount         = fee (ore)
      currency       = "sek"
      customer       = stripeCustomerId
      payment_method = stripePaymentMethodId
      off_session    = true
      confirm        = true
      metadata       = { locationId, date, reservationId }

    webhook: payment_intent.succeeded
      status -> "no_show_charged" / "cancelled_charged"
      (condition-guarded; stream filter reserved->terminal sends the SMS)

    webhook: payment_intent.payment_failed
      status -> "no_show_charge_failed" / "cancelled_charge_failed"
      + PutItem into payment_delinquency with a Stripe payment link for
        manual settlement (existing pattern; a paid link later moves
        *_charge_failed -> *_charged - that transition deliberately does
        not re-trigger the SMS filters)
```

## Reservation item: attributes this adds

| Attribute | Type |
|---|---|
| stripeCustomerId | String (`cus_...`, set on setup_intent.succeeded) |
| stripePaymentMethodId | String (`pm_...`, same moment) |
| setupIntentId | String (`seti_...`, set at session creation) |
| feeAmount | Number (ore - snapshot the fee at booking time, not at charge time) |

PII/retention note: these ids are references into Stripe, not card data -
PCI stays Stripe's problem. They ride the existing reservation `ttl`.

## Webhook events (payments/stripe/variables.tf: reservation_events)

Target set once the handler implements this flow:

    setup_intent.succeeded          confirm booking, save card refs
    setup_intent.setup_failed       card never saved - reservation stays pending
    payment_intent.succeeded        fee charged - terminal *_charged
    payment_intent.payment_failed   fee failed  - terminal *_charge_failed + delinquency

The variable still carries the CURRENT handler's events - switch it and
the handler in the same release, not separately: subscribing to events the
handler 500s on makes Stripe retry until the endpoint is flagged.

## Edge cases the handler must own

- **`authentication_required` declines**: an off-session charge can be
  declined pending 3DS. Treat as payment_failed -> delinquency path; the
  payment link is where the customer authenticates.
- **Idempotency**: every transition is a conditional UpdateItem on the
  expected prior status - duplicate webhook deliveries and out-of-order
  events become no-ops.
- **Charge exactly once**: no-show-check must create the PaymentIntent
  with an idempotency key (e.g. `noshow-<reservationId>`) so a retried
  scheduler invocation can't double-charge.
- **Fee disclosure**: the fee amount and cutoff time shown at booking are
  what make the charge defensible in a dispute - snapshot both on the
  reservation item.
