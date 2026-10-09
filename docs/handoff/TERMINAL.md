# Card terminals (Stripe Terminal) - handoff

In-person card / Apple Pay / Google Pay payments in the restaurant, taken on
Stripe readers. The money goes to the **restaurant's** Stripe account (the
readers and every payment live on its connected account), exactly like
online payments.

## What already exists (operator side - sbs-admin)

Per restaurant location, an operator (sbs-admin -> customer -> Locations ->
Card terminals -> Manage):

1. **Enables terminals**: creates a Stripe *Terminal Location* (Swedish
   address - required in SE) on the restaurant's connected account.
2. **Registers readers** with the pairing code shown on the reader
   (test mode: `simulated-wpe` = simulated WisePOS E), lists them
   (online/offline), removes them.

Guards: the tenant's plan must include the `terminal` feature, and the
connected account must have `charges_enabled` (Stripe onboarding done).
Deleting a location removes its readers and Terminal Location in Stripe.

Stored on the location row (location table, `TENANT#<t>` / `LOCATION#<l>`):

```json
"terminal": {
  "locationId": "tml_...",        // Stripe Terminal Location id
  "accountId":  "acct_...",       // connected account it lives on (location override or tenant's)
  "displayName": "Roma Södermalm",
  "address": { "line1": "...", "postalCode": "118 21", "city": "Stockholm", "country": "SE" }
}
```

## What the backend builds (application repo) - taking a payment

Server-driven integration (works with smart readers S700/S710/WisePOS E from
a web till; no native app needed). Every call: platform key +
`Stripe-Account: <terminal.accountId>`.

1. Till lists the location's readers:
   `GET /v1/terminal/readers?location=<terminal.locationId>` (show online ones).
2. Create the payment:
   `POST /v1/payment_intents` `amount`, `currency=sek`,
   `payment_method_types[]=card_present`, `capture_method=automatic`,
   `metadata[tenantId|locationId|orderId]` (+ `application_fee_amount` if the
   platform takes a fee).
3. Send it to the reader:
   `POST /v1/terminal/readers/<readerId>/process_payment_intent` `payment_intent=<pi>`.
   The guest taps / inserts the card (PIN is often required in Sweden - SCA).
4. Result: webhook on the Connect endpoint - `terminal.reader.action_succeeded`
   / `terminal.reader.action_failed` and `payment_intent.succeeded` (with
   `event.account` = the restaurant). Mark the order paid on success.
   Cancel a stuck action: `POST /v1/terminal/readers/<id>/cancel_action`.
5. Refunds: `POST /v1/refunds` `payment_intent=<pi>` (same `Stripe-Account`).

Tenant check as everywhere: the `locationId` must belong to the caller's
tenant; read `terminal.accountId` from the location row - never from the
request.

Testing without hardware (test mode): register `simulated-wpe` in sbs-admin,
then after step 3 call
`POST /v1/test_helpers/terminal/readers/<readerId>/present_payment_method`.

### Webhook events - add with the handler, not before

`terminal.reader.action_succeeded` and `terminal.reader.action_failed` are
**not** subscribed yet. Add them to the endpoint whose Lambda handles them
(`payments/stripe` event lists) in the same release as the handler code -
subscribing first makes Stripe retry events the deployed handler rejects.

## Frontend (admin-front-end) - the till

"Pay by card" on an order: pick a reader (online ones from step 1), show
"Waiting for card…", then success / declined (offer retry or another
reader). Show `payments_not_ready` / `feature_not_in_plan` errors per the
error contract.

## Stripe dashboard (platform owner)

- The Lambda key (`<env->stripe/api-key`) needs **Terminal: Write**
  (locations, readers, reader actions) in addition to its current
  permissions.
- Readers: the restaurant orders them in its own Stripe Dashboard
  (Terminal -> Hardware shop) - or the platform orders on its behalf - then
  pairs them via sbs-admin.
