# Card terminals (Stripe Terminal) - handoff

In-person card / Apple Pay / Google Pay payments in the restaurant, taken on
Stripe readers. The money goes to the **restaurant's** Stripe account (the
readers and every payment live on its connected account), exactly like
online payments.

## What already exists (operator side - Booqy Console)

Per restaurant location, an operator (Booqy Console -> customer -> Locations ->
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

## Taking a payment (built: application functions/terminal-payments)

"Ta betalt" in the admin app (`/ta-betalt`), staff and owners, plan feature
`terminal`. Server-driven integration, so no SDK and no native app: the
admin calls our API, our API calls Stripe, Stripe drives the reader.

- `GET /locations/{id}/card-payments/readers` - the location's readers
  (`terminal.locationId` on the restaurant's `terminal.accountId`).
- `POST /locations/{id}/card-payments` `{checkoutId, readerId, amount | orderId, note?}`
  creates ONE PaymentIntent per `checkoutId` (`card_present`, automatic
  capture, öre, metadata `tenantId|locationId|paymentId|date[|orderId]`) and
  sends it to the reader (`process_payment_intent`). Repeats of the same
  `checkoutId` return the same payment; "Försök igen" reuses the
  PaymentIntent, so nothing is ever charged twice.
- Outcome: the `terminal` Connect endpoint (payments/stripe, Function URL of
  terminal-payments): `payment_intent.succeeded|payment_failed`,
  `terminal.reader.action_succeeded|action_failed`, `charge.refunded`. The
  till also polls `GET .../card-payments/{paymentId}`, which asks Stripe
  itself once a try is a few seconds old.
- `.../cancel` (`cancel_action`), `.../retry`, `.../refund` (owner),
  `.../receipt` (GET the Swedish receipt, POST `{email}` to e-mail it),
  `.../simulate` (test mode only: `present_payment_method` on a simulated
  reader).
- An unpaid order (`pending_payment`) can be paid at the till: its online
  Checkout Session is expired first, then the order settles exactly like an
  online payment (confirmed, number, receipt e-mail, kitchen ticket).

Records: order table `CARD#<date>#<paymentId>` + pointer `CID#<paymentId>`
(retention, guest privacy and Statistik cover them).

Testing without hardware (test mode): register `simulated-wpe` in Booqy
Console, take a payment in admin and press "Simulera kort" (or "Simulera
nekat").

## Stripe dashboard (platform owner)

- The Lambda key (`<env->stripe/api-key`) needs **Terminal: Write**
  (locations, readers, reader actions) in addition to its current
  permissions.
- Readers: the restaurant orders them in its own Stripe Dashboard
  (Terminal -> Hardware shop) - or the platform orders on its behalf - then
  pairs them via Booqy Console.
