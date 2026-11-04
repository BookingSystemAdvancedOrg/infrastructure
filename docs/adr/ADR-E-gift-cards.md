# ADR-E: Gift cards (sell online, redeem online and in Kassa, accounting)

**Status:** Proposed
**Date:** 2026-11-01
**Deciders:** Owner (product), orchestrator (contracts); **accountant** (VAT and BAS treatment) and lawyer (validity, withdrawal right)
**Run:** built in Run 2

## Context

Restaurants sell presentkort on paper today, outside Booqy. All online money
is taken on the restaurant's Stripe connected account (BR-REST-088) with
idempotency keys (BR-NFR-019) and confirmed only by Stripe (BR-NFR-021).
Kassa bills hold `payments[]` and every receipt needs a control code
(BR-REST-052); the journal is append-only. Bokföring rebuilds one balanced
verifikation per location and day from source records (BR-REST-089) with
BAS mapping per role (BR-REST-090). VAT is 12% food, 25% alcohol, 6%
takeaway in its period (BR-NFR-030), so a restaurant gift card can pay for
supplies at different rates.

## Decision

1. **Sell on the restaurant site** at `/presentkort`: fixed amounts set by
   the owner (default 250/500/1 000 SEK) or a custom amount (100-5 000 SEK),
   buyer email, optional recipient name/email and a message (max 300).
   Stripe PaymentIntent on the connected account, idempotency key
   `giftcard-<purchaseId>`, metadata `kind=giftcard`. Turnstile and request
   guard on checkout (BR-NFR-014).
2. **Issue only from Stripe**: the existing `stripe-webhook` dispatches
   `payment_intent.succeeded` with `kind=giftcard` to the gift-cards Lambda
   through the `stripe.event` hook (CONTRACTS.md section 9, built in Run 0),
   which creates the card in one transaction (CARD +
   CODE + issue TX, all `attribute_not_exists` keyed by `purchaseId`).
   The handler first checks that the event's `account` is the
   `stripeAccountId` the purchase was created on and ignores it otherwise
   (`result: ignored:account_mismatch`): the webhook forwards whatever
   connected account sent `metadata.kind=giftcard`, so another
   restaurant's account must never issue, refund or dispute this
   restaurant's cards. Required test: same event from a foreign account
   changes nothing.
3. **Code**: 16 characters Crockford base32 (80 bits) shown as
   `XXXX-XXXX-XXXX-XXXX`, stored only as HMAC-SHA256 with a pepper secret
   (`<prefix>gift-cards/code-pepper`) plus `last4`. Sent once by email to the
   recipient (or buyer) by invoking `notification:live` with the code in the
   payload only (CONTRACTS.md 9.4; never stored, so no table stream). Owners
   never see the full code, and because it is never stored it cannot be
   re-sent either: E10 "Skicka ny kod" **rotates** the code (new `CODE#`
   row, old one deleted, `codeHmac`/`last4` replaced on the card in one
   transaction, then the new code is emailed as `gift-cards.code-resend`).
   The old code stops working at once, so the admin asks the owner to
   confirm before calling E10 and shows the new `last4` afterwards
   (decided 2026-11-04, DECISIONS.md). Bearer instrument: whoever has the
   code may use it.
4. **Balance ledger**: `balanceOre` on the card and an append-only TX row
   per change, written in one transaction with a condition
   (`balanceOre >= :amount AND version = :v AND status = active AND
   expiresAt > :now`). The TX id is client-supplied (Kassa `paymentId`,
   order id), so a retry never debits twice.
5. **Partial redemption online**: the order checkout (`payment-intent`)
   accepts `giftCardCode` and calls the `checkout.giftcard` hook (Run 0
   builds the call site); gift-cards debits `min(balance, total)` with TX id
   `order-<orderId>` and charges the rest by card. If the order fails or
   expires, the existing expiry path writes a `reverse` TX
   (`reverse-order-<orderId>`). An order fully covered by the card skips
   Stripe and is confirmed by the gift-cards debit.
6. **Partial redemption in Kassa**: new bill payment kind `giftcard`
   (`{paymentId, kind: giftcard, amountOre, cardLast4, cardId}`), stored
   with method `Presentkort`; Kassa verifies and reverses through the
   `kassa.giftcard` hook (Run 0 builds the Kassa side). Staff key
   in the code, see the balance, redeem; undo before the receipt reverses
   it. The receipt prints "Presentkort ****1234, kvar 150 kr" and the
   control system gets the payment means as a non-cash voucher. The sale
   and its VAT are recorded as usual on the receipt.
7. **Expiry**: default validity 24 months from purchase (owner may choose
   12-60 months); never shorter than 12. The date is shown on the purchase
   page, in the email and on balance checks. A nightly job marks cards past
   `expiresAt` as `expired` and writes an `expire` TX of the remaining
   balance (idempotent TX id `expire-<cardId>`). Owners may extend a card
   (adjust TX).
8. **VAT and accounting: treated as a multi-purpose voucher (flerfunktionsvoucher,
   ML 2023:200, 9 kap.)** because the VAT rate is not known at issue (food
   12%, alcohol 25%, takeaway 6%). **Needs accountant review; the
   feature's STATUS row carries "needs accountant review" until signed
   off.** Entries per location and day (in the existing `build_entry`):
   - Sale: debit Stripe settlement (existing role), credit **2421 Ej inlösta
     presentkort** (new role `giftCardLiability`). No output VAT.
   - Redemption (online or Kassa): the normal sales and VAT lines of the
     order/bill; the payment side debits 2421 instead of Stripe/cash.
   - Expiry (breakage): debit 2421, credit **3990 Övriga ersättningar och
     intäkter** (new role `giftCardBreakage`), no VAT.
   - Refund (owner, within the withdrawal period): reverse of the sale.
   The location of a sale is the location the guest bought from (site
   location picker), so cross-location redemption moves the liability
   between locations of the same legal entity; a monthly
   "presentkortsskuld" figure (sum of balances) is shown for reconciliation.
9. **Stripe disputes/refunds** arrive through the `stripe.event` hook
   (account-checked, decision 2). A lost dispute (`charge.dispute.closed`
   with `status: lost`; a won one is ignored) voids the card: one
   `void-<chargeId>` TX of the remaining balance, channel `system`,
   idempotent (`already_void` on replay or on an already void card).
   `charge.refunded` is meant to void the card **only on a full refund**
   (`amount_refunded == amount`); a **partial refund** must not void a
   card the guest still holds and is instead flagged on the card for the
   owner to settle by hand (E8 adjust or E9 refund). **As built on
   `build/run-2-integration` the handler voids on every `charge.refunded`
   whatever the refunded amount and writes no flag**; the split is a code
   follow-up (DECISIONS.md 2026-11-04). The E9 owner refund is a Stripe
   refund of the unused part and voids the card itself.

## Data model

Table `<prefix>gift-cards` (PAY_PER_REQUEST, PITR, deletion protection in
prod, TTL `ttl` only on purchase holds). GSIs:
`byLocationDay` (`GSI1PK = TENANT#<t>#LOC#<l>#<yyyy-mm-dd>`, `GSI1SK =
<at>#<txId>`, TX rows only, for Bokföring) and `byExpiry` (sparse, active
cards with balance: `GSI2PK = EXPIRY#<yyyy-mm-dd>`, `GSI2SK = <t>#<cardId>`,
read only by the nightly job).

| PK | SK | Item |
|---|---|---|
| `TENANT#<t>` | `SETTINGS` | `enabled`, `amountsSek[]`, `customMinSek`, `customMaxSek`, `validityMonths`, `version` |
| `TENANT#<t>` | `PURCHASE#<purchaseId>` | `locationId`, `amountOre`, `paymentIntentId`, `buyerEmail`, `recipientName?`, `recipientEmail?`, `message?`, `status` (`pending` \| `issued` \| `failed`), `cardId?`, `ttl` = +7 days while pending (removed on issue) |
| `TENANT#<t>` | `CARD#<cardId>` | `codeHmac`, `last4`, `initialOre`, `balanceOre`, `status` (`active` \| `used` \| `expired` \| `void`), `soldAtLocationId`, `purchaseId`, `purchasedAt`, `expiresAt`, `buyerEmail`, `buyerEmailHash`, `recipientName?`, `recipientEmail?`, `recipientEmailHash?`, `message?`, `version` |
| `TENANT#<t>` | `CODE#<codeHmac>` | `cardId` (uniqueness and lookup) |
| `TENANT#<t>` | `CARD#<cardId>#TX#<txId>` | `kind` (`issue` \| `redeem` \| `reverse` \| `expire` \| `adjust` \| `refund` \| `void`), `amountOre` (signed), `balanceAfterOre`, `channel` (`online` \| `kassa` \| `admin` \| `system`), `ref{orderId? \| billId?, paymentId?}`, `locationId`, `at`, `by?`; never updated |

Email hashes are `sha256(tenant|email)` for erasure lookups. Amounts in
öre.

## API routes

Errors `{error, code, field?}`. Codes travel only in request bodies.

| # | Method | Path | Auth | Role | Request -> response |
|---|---|---|---|---|---|
| 1 | GET | `/public/locations/{locationId}/gift-cards/offer` | public | guest | -> `{amountsSek[], customMinSek, customMaxSek, validityMonths}` |
| 2 | POST | `/public/locations/{locationId}/gift-cards/checkout` | Turnstile + request guard | guest | `{purchaseId, amountSek, buyerEmail, recipientName?, recipientEmail?, message?, turnstileToken}` -> `{clientSecret, amountSek, expiresAt}` |
| 3 | POST | `/public/locations/{locationId}/gift-cards/balance` | Turnstile + request guard | guest | `{code, turnstileToken}` -> `{balanceSek, expiresAt, status}`; any miss 404 |
| 4 | GET | `/tenant/gift-cards/settings` | JWT | owner | -> settings |
| 5 | PUT | `/tenant/gift-cards/settings` | JWT | owner | `{enabled, amountsSek, customMinSek, customMaxSek, validityMonths, version}` -> settings |
| 6 | GET | `/tenant/gift-cards?status=&cursor=` | JWT | owner | -> `{cards[{cardId, last4, initialSek, balanceSek, status, expiresAt}], liabilitySek, cursor}` |
| 7 | GET | `/tenant/gift-cards/{cardId}` | JWT | owner | -> card + `transactions[]` |
| 8 | POST | `/tenant/gift-cards/{cardId}/adjust` | JWT | owner | `{txId, expiresAt?, reason}` -> card (extend validity) |
| 9 | POST | `/tenant/gift-cards/{cardId}/refund` | JWT | owner | `{txId, reason}` -> card (`void`); Stripe refund of the unused part, key `giftcard-refund-<txId>` |
| 10 | POST | `/tenant/gift-cards/{cardId}/resend` | JWT | owner | `{to: buyer \| recipient}` -> 202 `{last4}` (a new code; the old one is void; active cards only) |
| 11 | POST | `/locations/{locationId}/gift-cards/lookup` | JWT | owner, staff | `{code}` -> `{cardId, last4, balanceSek, expiresAt, status}` |
| 12 | POST | `/locations/{locationId}/gift-cards/redemptions` | JWT | owner, staff | `{txId (= Kassa paymentId), code, amountOre, billId}` -> `{balanceAfterSek, txId}` |
| 13 | POST | `/locations/{locationId}/gift-cards/redemptions/{txId}/reverse` | JWT | owner, staff | `{}` -> `{balanceAfterSek}` (only before the bill's receipt) |

Online redemption is a new optional field `giftCardCode` on the existing
order checkout body (shared change in `payment-intent`), not a new route.

Errors: 400 `unsupported fields`, `invalid_amount`, `invalid_email`,
`message_too_long`, `invalid_validity`, `turnstile_failed`; 403
`feature_not_in_plan`, `owner_only`; 404 unknown/foreign location or card,
wrong code, feature off (public); 409 `insufficient_balance`, `card_expired`,
`card_void`, `changed_retry`, `receipt_issued` (reverse after receipt),
`refund_window_passed`; 429 request guard; 502 `stripe_unavailable`.

Idempotency: `purchaseId` (Stripe idempotency key and conditional Put),
`txId` on every balance change (TX row `attribute_not_exists`; a retry with
the same `txId` returns the stored result, a different amount gives 409
`changed_retry`); webhook issue keyed by `purchaseId`.

## Events

Bus `<prefix>booqy-events`, source `booqy.gift-cards`. Every detail has
`tenantId`, `occurredAt`, `version: 1`, `cardId`. No codes, names or emails.

| detail-type | extra detail |
|---|---|
| `GiftCard.Sold` | `locationId`, `amountOre`, `expiresAt` |
| `GiftCard.Redeemed` | `locationId`, `amountOre`, `balanceAfterOre`, `channel`, `txId` |
| `GiftCard.RedemptionReversed` | `locationId`, `amountOre`, `txId` |
| `GiftCard.Expired` | `amountOre` (breakage) |
| `GiftCard.Refunded` | `amountOre` |

Bokföring does not consume events; `shared/accounting.location_events`
calls the `accounting.events` hook, and gift-cards answers from TX rows by
`byLocationDay`. The two account roles are added by Run 0.

## Terraform modules

- `infrastructure/gift-cards/`: table + GSIs, Lambda `gift-cards` (API,
  webhook issue, nightly expiry at 02:30 Europe/Stockholm via Scheduler),
  pepper secret `<prefix>gift-cards/code-pepper` (random, Terraform-created),
  logs, alarms, role. Root `gift-cards.tf`; routes
  `network/api-gateway/gift-cards-routes.tf` (public routes throttled like
  other public routes).
- IAM (new role): table CRUD, pepper secret read, Stripe secret read,
  Turnstile secret read, request-guard table, location/tenant read,
  `events:PutEvents`.
- **IAM change to existing roles (call out):** `stripe-webhook`,
  `payment-intent`, `webhook-payment-intent` (order expiry path), `kassa`,
  `accounting`, `guest-privacy` and `tenant-purge` get
  `lambda:InvokeFunction` on `gift-cards:live` only (hooks, decided:
  invoke, no table or pepper access on those roles). The gift-cards role
  gets invoke on `notification:live`; notification gets nothing new.
- The module's `wiring` output lists the function for `lambda_releases`,
  `tenant_aware_role_names`, `staff_check_role_names`. Purge is the
  `tenant.purge` hook: SETTINGS, PURCHASE and contact fields go now; CARD,
  CODE and TX rows get `ttl` = end of the 7th year after the last TX
  (bookkeeping retention, as for receipts).

## Entitlement name

`giftCards` (`entitlements.features.giftCards`). Off -> 403 on JWT routes,
404 on public routes, the checkout field `giftCardCode` refused with 400
`gift_cards_off`. `/site-config` exposes `tenant.features.giftCards`.
Kassa redemption also needs `kassa`.

## Plan availability (target)

starter and growth. Run 0 ships `false` in every plan.

## UI placement

- Guest site: `/presentkort` (choose amount, details, pay, "Koden kommer
  via e-post") and `/presentkort/saldo` (check balance), site-kit feature
  folder `presentkort`, lazy in `sitePages`, linked in nav when the feature
  is on. Order checkout (`bestall`): "Har du ett presentkort?" field.
- Admin, group `restaurangen`, new item `/presentkort` "Presentkort"
  (feature `giftCards`, ownerOnly): list, search by last 4, card detail
  with history, "Förläng", "Återbetala", "Skicka igen", settings card, total
  "Presentkortsskuld".
- Admin, `/kassa` (group `passet`): "Presentkort" payment button on a bill
  (code field, balance, amount).
- Admin, `/installningar` tab `bokforing`: two new account rows (2421, 3990)
  in `BokforingCard`.

## External dependencies

Stripe (existing, test mode in dev), Turnstile (existing), fiskaly control
system (existing; voucher payment means). Nothing new is mocked; no new
approvals except the accountant and lawyer reviews.

## Privacy and GDPR

- Data: buyer email, recipient name/email, message; codes as HMAC only.
- Legal basis: contract (art. 6(1)(b)); bookkeeping obligation for amounts
  (art. 6(1)(c)).
- Retention: contact fields and message removed by the gift-cards nightly
  job (not data-retention, which stays unchanged) 24 months after the card
  is `used`, `expired` or `void` (contact rule, BR-NFR-008); card amounts
  and TX rows kept 7 years (receipts rule).
- Erase: `guest-privacy` erase calls the `privacy.erase` hook; gift-cards
  finds cards by email hash and removes buyer
  and recipient contact and message; the card and balance stay valid (it is
  a bearer instrument and a bookkeeping record). Export includes the cards.
- Storage registry (site-kit `storageRegistry.ts`): new
  `GIFT_CARD_PURCHASE_KEY` = sessionStorage `booqy-giftcard-purchase`
  (category nödvändig, keeps `purchaseId` across the 3-D Secure redirect,
  removed after the thank-you page). Stripe Elements is already listed.

## Swedish legal notes (human check)

- **VAT: multi-purpose voucher (ML 2023:200, 9 kap.; directive 2016/1065)
  decided; accountant must confirm**, including breakage to 3990 without VAT
  and the use of BAS 2421.
- Validity: no statutory minimum; Konsumentverket/ARN practice treats under
  one year as unreasonable, and an undated card may run to the 10-year
  limitation (preskriptionslagen). Confirm 24 months default and whether an
  expired card must still be honoured.
- Withdrawal right (distansavtalslagen 2 kap.) for online gift card sales:
  confirm 14 days applies and the refund route covers it.
- Kassaregister (SKVFS 2021:16): confirm how a voucher payment and a
  receipt paid fully by gift card are reported to the control system.

## Test plan

Two-tenant fixtures, `mock_aws()`, Stripe test helpers or a fake. Every
route: happy path, validation error, wrong role, foreign tenant 404,
entitlement off refused, idempotent retry.

| # | Validation | Wrong role | Foreign 404 | Off | Retry |
|---|---|---|---|---|---|
| 1 | n/a | n/a (public) | inactive tenant's location 404 | 404 | n/a |
| 2 | 50 SEK, bad email, no Turnstile | n/a | inactive tenant 404 | 404 | same purchaseId -> same clientSecret |
| 3 | malformed code 404 | n/a | B's code at A's location 404 | 404 | n/a |
| 4 | n/a | staff 403 | own tenant only | 403 | n/a |
| 5 | validity 6 | staff 403 | n/a | 403 | stale version 409 |
| 6 | bad status | staff 403 | n/a | 403 | n/a |
| 7 | n/a | staff 403 | B's cardId 404 | 403 | n/a |
| 8 | shorter expiry 400 | staff 403 | B's card 404 | 403 | same txId -> one TX |
| 9 | after window 409 | staff 403 | B's card 404 | 403 | same txId -> one Stripe refund |
| 10 | bad target; expired or void card 409 | staff 403 | B's card 404 | 403 | resend twice -> two mails, two codes; only the latest code is accepted by lookup, balance and redemption |
| 11 | missing code 400 | staff other location 404 | LOC_B 404 | 403 | n/a |
| 12 | amount > balance 409 | staff other location 404 | B's code 404 | 403 | same txId -> one debit |
| 13 | after receipt 409 | staff other location 404 | B's txId 404 | 403 | second reverse -> same balance |

Plus: concurrent redemptions of one card (two txIds, balance never
negative); webhook replay issues one card; online order partly paid then
expired reverses once; Kassa undo before receipt reverses; nightly expiry
idempotent and resumable; Bokföring entry balanced with sale, redemption and
breakage lines and unchanged totals for days without gift cards; code never
logged or stored in plaintext (test greps items and logs). **Two-tenant
isolation test:** a code issued by TENANT_A gives 404 at TENANT_B's site and
Kassa; A's routes with B's cardId/txId 404; A's Bokföring never includes B's
TX rows.

## Alternatives considered

- **Single-purpose voucher (VAT at sale)**: simpler entries, but the rate is
  unknown at sale; wrong for a restaurant. Rejected pending accountant.
- **Stripe Customer balance / promotion codes**: tied to Stripe online only,
  no Kassa redemption. Rejected.
- **Storing codes encrypted for owner display**: a leaked admin session
  becomes a leak of spendable money. Rejected for HMAC + last 4.

## Open questions

1. Sell gift cards at the till (Kassa) too? Out of scope for Run 2.
2. Scheduled delivery to the recipient on a chosen date?
3. Owner-printable PDF card (print-collateral style)?
