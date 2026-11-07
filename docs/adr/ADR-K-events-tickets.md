# ADR-K: Events and tickets (sell, scan, account)

**Status:** Proposed
**Date:** 2026-11-02
**Deciders:** Owner (product, pricing of the feature, transfer and resale policy), orchestrator (contracts); **accountant** (Swedish VAT on tickets, advance payments, BAS accounts); lawyer (distance-sale withdrawal right for dated events, resale terms)
**Run:** scaffolded in the Run 0 addendum, built in Run 2

Anything marked **[NEEDS YOUR OK]** is a proposal for the owner, not a
decision.

## Context

Restaurants run quiz nights, wine dinners, tasting menus and New Year
seatings and sell seats through a ticketing site that charges per ticket and
keeps the guest data. Booqy already has the restaurant's Stripe connected
account with idempotent PaymentIntents confirmed only by webhook
(BR-REST-088, BR-NFR-019/021), Turnstile and the request guard on public
checkout, `notification` for email and SMS, Bokföring that rebuilds one
balanced entry per location and day from source records through the
`accounting.events` hook (gift cards, ADR-E), insights with owner/staff
money stripping, the published floor plan for table picking
(`layout-editor`, read-only reuse like ADR-F), and the storage registries for
anything a browser keeps. It has no event model, no QR, no Wallet passes.

## Decision

1. **An event is a location thing with occurrences.** `EVENT#` holds the
   description, image (menu image bucket, existing presigned upload),
   settings and an optional recurrence; `OCC#` is one dated occurrence with
   its own capacity, sales window, status and sold/held counters. A
   one-off event has one occurrence. **Recurring series** are generated
   ahead (weekly or monthly on a weekday, `until` at most 12 months,
   exceptions list) by the publish step, each occurrence editable or
   cancellable alone; the generator is idempotent by `(eventId, startAt)`.
2. **Ticket types and tiers.** `TYPE#` has name, price (öre, incl. VAT),
   the VAT rate chosen by the owner from the rates the accountant approves
   (section "Swedish legal notes"), optional per-type capacity, optional
   tier window (`availableFrom`/`availableUntil` or `untilSold: n` for
   "early bird"), `includes` text and `perOrderMax`. Free tickets (price 0)
   are allowed and skip Stripe.
3. **Capacity is a conditional counter.** Checkout reserves `qty` on the
   occurrence (`sold + held + :q <= capacity`) and per type when the type
   has a capacity, in one transaction with the pending `ORDER#` (`ttl` 15
   minutes). The webhook moves `held` to `sold`; expiry (nightly plus a
   5-minute sweep in the same Lambda via Scheduler) releases the hold.
   Optional **table pick** on the published floor plan: when the owner
   turns it on for an occurrence, the checkout also takes a `tableIds[]`
   choice and the feature holds the tables as a `HELD` reservation through
   `create-pending-reservation` (the ADR-F path), converting on payment, so
   the dining room cannot be double-sold between tickets and bookings.
4. **Prepaid checkout on the restaurant's Stripe account.** Public route
   with Turnstile and the request guard; PaymentIntent on the connected
   account (`Stripe-Account`), idempotency key `ticket-<orderId>`, metadata
   `kind=ticket`, `tenantId`, `orderId`. Issue only from Stripe: the
   existing `stripe-webhook` forwards `metadata.kind == "ticket"` events to
   the `stripe.event` hook with target events-tickets (Run 0 addendum
   hotspot, same shape as gift cards), which checks `account` against the
   order's `stripeAccountId` and issues tickets in one transaction (TICKET
   rows + CODE rows + `sold` counter + order `paid`). The buyer gets one
   email with every ticket (QR, Wallet links, the ticket page link) through
   `notification` (kind `events-tickets.tickets`), rendered by the feature.
   A receipt for the online sale is that email **[NEEDS YOUR OK: lawyer or
   accountant to confirm the email receipt content satisfies bokföringslagen
   for a distance sale; no Kassa receipt for online ticket sales]**.
5. **Ticket code and QR.** `ticketId` is a ULID; the QR encodes
   `<ticketId>.<sig>` where `sig = HMAC-SHA256(scanKey, ticketId)[:16]` and
   `scanKey = HMAC-SHA256(pepper, occurrenceId)` with the pepper in
   `${prefix}events-tickets/code-pepper`. The scanner downloads the
   occurrence's `scanKey` with the guest list, so a scan verifies offline
   without a lookup; the server re-verifies on sync. Codes are stored as
   `codeHmac` only (ADR-E rule). The ticket page link is an HMAC token in
   the URL fragment like the booking manage links.
6. **Wallet passes.** Both are generated on request from the ticket page
   (never stored) and show the same facts: event title, start time, place
   (the location's name), ticket type, holder name and the QR (the same
   `<ticketId>.<sig>` payload the door scanner verifies, with the last 8
   characters of the ticket id as the printed code). Apple Wallet: a
   `.pkpass` (event ticket style: title primary; start time and place
   secondary; holder and ticket type auxiliary; `relevantDate` = start,
   `expirationDate` = end) signed with the platform Pass Type ID
   certificate in `${prefix}events-tickets/apple-pass`. Google Wallet:
   a "Save to Google Wallet" link carrying a JWT signed with the service
   account in `${prefix}events-tickets/google-wallet`. The Google
   `EventTicketClass` (`<issuerId>.<classId or booqy-event-ticket>`) is
   created once by hand and the JWT references it by id; it is never sent
   inline, because an inline class pushed the live JWT over the 1800
   character limit of the save link. The JWT carries only the ticket
   object, with the long strings capped (event title, place and holder
   name 30, ticket type 20 characters, at most 3 UTF-8 bytes per
   character, an ellipsis when cut; the full values stay on the ticket
   page and the Apple pass). The JWT length follows UTF-8 bytes, so the
   finished link is measured: over 1700 characters the strings are
   shortened step by step and last the optional text modules dropped. The
   start time is only in `validTimeInterval`. v1 has no pass push
   updates: a transferred or refunded ticket is simply refused at the door
   and the ticket page says so. When a secret is missing, empty, unparseable
   or lacks a field the kind is hidden; a complete secret with bad key
   material still shows the kind and answers 404 on click, as does any
   pass that cannot be built, with no detail (feature works without
   Wallet).
   **[Human actions: Apple Developer account and Pass Type ID; Google
   Wallet issuer account and the one-time EventTicketClass.]**
7. **QR scanning and guest list in admin** (`/evenemang/<eventId>/insläpp`,
   owner and staff): camera scanning with the browser `BarcodeDetector`
   API and a typed-code fallback (no new dependency in v1; a decoding
   library needs the orchestrator's approval), the guest list sorted by
   holder name with search, "Släpp in" per ticket, counters (insläppta /
   sålda / kapacitet as a `Bar variant="meter"`). **Offline:** the guest
   list, `scanKey` and queued check-ins live in IndexedDB
   (`booqy-event-scan-<occurrenceId>`, storage registry entry, deleted
   after sync at the event's end + 1 day); check-ins sync in batches with
   client ids, duplicates are reported back ("redan insläppt 19:02 av Ali")
   and shown. Walk-up sales: the owner prints a poster QR (print-collateral
   style, existing pattern) that opens the public event page; door payment
   happens on the guest's phone, so no Kassa changes are needed for v1.
8. **Transfer and resale at face value.** The holder opens the ticket page
   and either gives the ticket away (transfer: new holder's email, free) or
   lists it for resale at its own price (what was paid, never the type's
   current price; free tickets cannot be listed). The listing is shown on
   the restaurant's public event page whenever resale is on (K16
   `resale[]`), and the buyer picks listed tickets explicitly (K17
   `resaleTransferIds`, 1-4 per order): the buyer pays face value on the
   restaurant's account, the seller is refunded the same amount on the
   original PaymentIntent (partial refund, idempotency key
   `ticket-resale-<transferId>`), the old ticket is voided and a new one
   issued with the same type, price and VAT rate, all in one DynamoDB
   transaction. The 15-minute hold is a claim on the listing, no capacity
   moves. The ADR's earlier "next checkout takes the listed ticket first" and
   "ledig igen" email are not built (see DECISIONS.md 2026-11-06). A resale
   publishes `Ticket.Transferred kind=resale` only, not `Ticket.Sold`.
   Stripe fees on both legs are the restaurant's
   **[NEEDS YOUR OK: or add a resale fee; v1 has none]**. Owners may turn
   transfer and resale off per event (resale default off). Both are refused
   within 2 hours of the start.
9. **Refunds.** Owner refund per ticket or whole order (Stripe refund on the
   connected account, key `ticket-refund-<ticketId>`), and **cancel an
   occurrence = mass refund** as a 202 job that refunds every paid order
   with per-ticket idempotency and emails the buyers; resumable by the
   sweep. Refund policy text per event is the owner's; the withdrawal
   right exception for dated leisure events (distansavtalslagen 2 kap.
   11 § 12) is noted for the lawyer below.
10. **Feeding Statistik, Bokföring and Kassa.** Statistik: insights calls a
    new hook `insights.events` (`locationIds`, `first`, `last`) and the
    feature answers `{occurrences, ticketsSold, revenueOre, checkedIn}` per
    day, shown in a slot on the Statistik page (money stripped for staff by
    the existing `without_money`). Bokföring: the feature answers the
    existing `accounting.events` hook from `TX#` rows (`byLocationDay`):
    sale -> debit Stripe settlement, credit `ticketSales<Rate>` with output
    VAT at the ticket type's rate (advance payment taxed when received;
    accountant to confirm, section "Swedish legal notes"); refund ->
    reverse; resale -> sale + refund the same day, net zero. New roles
    `ticketSales` with the VAT rates the accountant approves
    **[NEEDS YOUR OK: BAS accounts; proposal 3010-series split by rate]**.
    Kassa: v1 **does not** add a ticket payment kind to Kassa; a ticket
    that includes food is consumed against the prepaid amount and the
    Kassa bill, if any, covers extras only. A `kassa.ticket` hook (same
    shape as `kassa.giftcard`) is the v1.1 candidate once the control
    system voucher question that blocks E is settled **[NEEDS YOUR OK]**.

## Data model

Table `<prefix>events-tickets` (PAY_PER_REQUEST, PITR, deletion protection
in prod, TTL `ttl` on pending orders and transfers, no stream).

| PK | SK | Item |
|---|---|---|
| `TENANT#<t>` | `EVENT#<eventId>` | `locationId`, `title`, `description`, `imageKey?`, `status` (`draft` \| `published` \| `cancelled`), `series?{freq: weekly \| monthly, weekday, until, exceptions[]}`, `settings{perOrderMax, transferAllowed, resaleAllowed, refundPolicy, tablePick}`, `version`, `createdAt`, `updatedBy` |
| `TENANT#<t>` | `EVENT#<eventId>#OCC#<startAt>` | `occurrenceId` (= `<eventId>-<startAt>`), `endAt`, `doorsAt?`, `capacity`, `sold`, `held`, `checkedIn`, `salesOpenAt`, `salesCloseAt`, `status` (`scheduled` \| `cancelled` \| `done`), `layoutVersionId?`, `version` |
| `TENANT#<t>` | `EVENT#<eventId>#TYPE#<typeId>` | `name`, `priceOre`, `vatRate` (from the approved list), `capacity?`, `sold`, `tier?{availableFrom?, availableUntil?, untilSold?}`, `includes?`, `perOrderMax`, `sortOrder`, `version` |
| `TENANT#<t>` | `ORDER#<orderId>` | `occurrenceId`, `locationId`, `lines[{typeId, qty, priceOre}]`, `amountOre`, `buyerName`, `buyerEmail`, `buyerEmailHash`, `buyerPhone?`, `status` (`pending` \| `paid` \| `expired` \| `refunded` \| `partly_refunded`), `paymentIntentId?`, `stripeAccountId`, `tableIds?`, `reservationId?`, `ttl` while pending |
| `TENANT#<t>` | `TICKET#<ticketId>` | `orderId`, `occurrenceId`, `typeId`, `codeHmac`, `status` (`valid` \| `checked_in` \| `transferred` \| `refunded` \| `void`), `holderName?`, `holderEmail?`, `holderEmailHash`, `checkedInAt?`, `checkedInBy?`, `version` |
| `TENANT#<t>` | `CODE#<codeHmac>` | `ticketId` |
| `TENANT#<t>` | `TRANSFER#<transferId>` | `ticketId`, `kind` (`gift` \| `resale`), `toEmail?`, `toEmailHash?`, `priceOre`, `status` (`pending` \| `accepted` \| `sold` \| `expired` \| `cancelled`), `newTicketId?`, `ttl` |
| `TENANT#<t>` | `TX#<txId>` | `kind` (`sale` \| `refund` \| `resale_sale` \| `resale_refund`), `orderId`, `ticketIds[]`, `amountOre` (signed), `vatLines[{rate, netOre, vatOre}]`, `locationId`, `at`; never updated |
| `TENANT#<t>` | `JOB#<jobId>` | mass refund or series generation progress: `kind`, `cursor`, `done`, `counts`, `ttl` 7 days |

GSIs: `byOccurrence` (`GSI1PK = TENANT#<t>#OCC#<occurrenceId>`,
`GSI1SK = <holderName>#<ticketId>`, TICKET rows: guest list);
`byLocationDay` (`GSI2PK = TENANT#<t>#LOC#<l>#<day>`, `GSI2SK = <at>#<txId>`,
TX rows: Bokföring and insights). Public event list = Query
`begins_with(SK, EVENT#)` filtered `published` per location (small per
tenant; a location GSI is added if a tenant passes 200 events).

## API routes

Errors `{error, code, field?}`. Tokens in paths are HMAC link tokens, not
contact data.

| # | Method | Path | Auth | Role | Request -> response |
|---|---|---|---|---|---|
| K1 | GET | `/locations/{locationId}/events?status=&cursor=` | JWT | owner, staff | -> `{events[{eventId, title, status, nextOccurrence?, sold, capacity}], cursor}` |
| K2 | POST | `/locations/{locationId}/events` | JWT | owner | `{eventId, title, description, imageKey?, imageAlt?, occurrences[{startAt, endAt, capacity, salesOpenAt?, salesCloseAt?}], series?, ticketTypes[], settings}` -> 201 event (draft) |
| K3 | GET | `/locations/{locationId}/events/{eventId}` | JWT | owner, staff | -> event + occurrences + ticketTypes (staff: no revenue) |
| K4 | PUT | `/locations/{locationId}/events/{eventId}` | JWT | owner | event fields + `version` -> event |
| K5 | POST | `/locations/{locationId}/events/{eventId}/publish` | JWT | owner | `{version}` -> event (`published`), series occurrences generated |
| K6 | PUT | `/locations/{locationId}/events/{eventId}/ticket-types/{typeId}` | JWT | owner | type fields + `version?` -> type (client ULID) |
| K7 | DELETE | `/locations/{locationId}/events/{eventId}/ticket-types/{typeId}` | JWT | owner | -> 204 (only with `sold = 0`) |
| K8 | PUT | `/locations/{locationId}/events/{eventId}/occurrences/{occurrenceId}` | JWT | owner | `{capacity?, salesOpenAt?, salesCloseAt?, doorsAt?, version}` -> occurrence |
| K9 | POST | `/locations/{locationId}/events/{eventId}/occurrences/{occurrenceId}/cancel` | JWT | owner | `{jobId, version, message?}` -> 202 `{jobId, toRefund}` (mass refund) |
| K10 | GET | `/locations/{locationId}/events/{eventId}/occurrences/{occurrenceId}/guest-list` | JWT | owner, staff | -> `{scanKey, tickets[{ticketId, holderName, typeName, status, checkedInAt?}], counters}` |
| K11 | POST | `/locations/{locationId}/events/{eventId}/occurrences/{occurrenceId}/check-ins` | JWT | owner, staff | `{checkIns[{ticketId, sig, at, clientId}]}` (max 200) -> `{results[{clientId, status: ok \| already \| invalid \| void}]}` |
| K12 | GET | `/locations/{locationId}/events/{eventId}/orders?cursor=` | JWT | owner | -> `{orders[], cursor}` |
| K13 | POST | `/locations/{locationId}/events/tickets/{ticketId}/refund` | JWT | owner | `{txId, reason}` -> ticket (`refunded`) |
| K14 | GET | `/locations/{locationId}/events/jobs/{jobId}` | JWT | owner | -> `{kind, done, counts}` |
| K15 | GET | `/public/locations/{locationId}/events` | public | guest | -> `{events[{eventId, title, imageKey?, imageAlt?, nextOccurrence, fromPriceSek, soldOut}]}` |
| K16 | GET | `/public/locations/{locationId}/events/{eventId}` | public | guest | -> event + `occurrences[{occurrenceId, startAt, left, soldOut}]` + `ticketTypes[{typeId, name, priceSek, left?, available}]` + `tablePick?` |
| K17 | POST | `/public/locations/{locationId}/events/checkout` | public (Turnstile + request guard, throttle `public`) | guest | `{orderId, occurrenceId, lines[{typeId, qty}], buyerName, buyerEmail, buyerPhone?, tableIds?, turnstileToken}` -> `{clientSecret?, amountSek, expiresAt}` (no `clientSecret` when free: tickets issued at once) |
| K18 | GET | `/public/tickets/{token}` | public (token) | guest | -> `{event, occurrence, tickets[{ticketId, typeName, holderName, status, qr, priceOre, resale?, pendingTransfer?}], wallet{apple: bool, google: bool}, transferAllowed, resaleAllowed}` |
| K19 | GET | `/public/tickets/{token}/pass?ticketId=&kind=apple\|google` | public (token) | guest | -> `.pkpass` file or 302 to the Google save link |
| K20 | POST | `/public/tickets/{token}/transfers` | public (token) | guest | `{transferId, ticketId, kind, toEmail?}` -> 201 transfer |
| K21 | POST | `/public/ticket-transfers/{transferToken}/accept` | public (token) | guest | `{name}` -> `{ticketToken}` (gift) |
| K22 | DELETE | `/public/tickets/{token}/transfers/{transferId}` | public (token) | guest | -> 204 (cancel listing) |

Errors: 400 `invalid_capacity`, `invalid_price`, `invalid_vat_rate`,
`invalid_window`, `invalid_series`, `too_many_tickets`, `invalid_email`,
`turnstile_failed`, `invalid_sig`; 403 `feature_not_in_plan`, `owner_only`;
404 foreign/unknown location, event, ticket, token, feature off (public);
409 `sold_out`, `type_sold_out`, `sales_closed`, `has_sales` (delete type),
`invalid_state`, `transfer_closed`, `already_checked_in`, `changed_retry`,
`table_taken`; 429 request guard; 502 `stripe_unavailable`.

Idempotency: `eventId`, `typeId`, `orderId`, `transferId`, `txId`, `jobId`
are client ULIDs with conditional Puts; check-ins by `clientId`; Stripe
keys per order, refund and resale; webhook issue keyed by `orderId`.

## Events

Bus `<prefix>booqy-events`, source `booqy.events-tickets`. Common fields
`tenantId`, `occurredAt`, `version: 1`. No names or emails.

| detail-type | extra detail |
|---|---|
| `Event.Published` | `locationId`, `eventId`, `occurrences: int` |
| `EventOccurrence.Cancelled` | `locationId`, `eventId`, `occurrenceId`, `ticketsToRefund: int` |
| `Ticket.Sold` | `locationId`, `eventId`, `occurrenceId`, `orderId`, `qty: int`, `amountOre: int` |
| `Ticket.CheckedIn` | `locationId`, `occurrenceId`, `ticketId` |
| `Ticket.Transferred` | `locationId`, `occurrenceId`, `ticketId`, `newTicketId`, `kind: enum[gift,resale]` |
| `Ticket.Refunded` | `locationId`, `occurrenceId`, `ticketId`, `amountOre: int`, `by: enum[owner,cancellation]` |

Guest CRM (ADR-C) may later consume `Ticket.Sold` as a visit source
(`kind: event`); not in Run 2.

## Terraform modules

- `infrastructure/events-tickets/`: table + 2 GSIs, Lambda `events-tickets`
  (API, hooks, webhook issue, jobs: Scheduler every 5 minutes for hold
  expiry and job progress, nightly 02:45 Europe/Stockholm for retention),
  pepper secret (`random_password`), the two Wallet secrets (created
  empty, values by hand, `ignore_changes`), role, logs, Errors alarm.
- Root `events-tickets.tf`; routes `network/api-gateway/events-tickets-routes.tf`
  (public routes with `throttle = "public"`).
- IAM (new role): table CRUD, secrets get, Stripe secret read, Turnstile
  secret read, request-guard table, menu image bucket read (presigned
  image URLs), reservation and slot-occupancy item actions as
  `create-pending-reservation` for table pick (invoke
  `create-pending-reservation:live` instead if the reviewer prefers the
  channel pattern of ADR-L; decide in Run 2), tenant-context read,
  `events:PutEvents`, invoke `notification:live`.
- **IAM change to existing roles (call out, owner to approve):**
  `stripe-webhook`, `accounting`, `insights`, `guest-privacy` and
  `tenant-purge` get `lambda:InvokeFunction` on `events-tickets:live`.
- `wiring` output lists the function for `lambda_releases`,
  `tenant_aware_role_names`, `staff_check_role_names`.

## Entitlement name

`events` (`entitlements.features.events`). Off -> 403 on JWT routes, 404 on
public routes; `/site-config` exposes `tenant.features.events`. Table pick
also needs `reservations`.

## Plan availability (target)

starter and growth **[NEEDS YOUR OK; also whether Booqy takes a per-ticket
fee: v1 has none, the restaurant pays only Stripe]**. Run 0 addendum ships
`false` in every plan.

## UI placement

- Guest site: `/evenemang` (list), `/evenemang/:eventId` (detail, tickets,
  table pick, checkout), `/biljett#<token>` (tickets with QR, Wallet
  buttons, "Ge bort" / "Sälj vidare"), `/biljett/ta-emot#<transferToken>`;
  site-kit feature folder `evenemang`, lazy in `sitePages`, nav link
  "Evenemang" when on.
- Admin, group `restaurangen`, new item `/evenemang` "Evenemang" (feature
  `events`, not ownerOnly, tour `nav-evenemang`, after Webbplats): list,
  event editor (owner), occurrences, orders, the insläpp screen (staff and
  owner) with scanner and guest list, poster print.
- Admin `/statistik`: slot `statistik.events` (tickets sold, revenue,
  check-in rate; staff without money).
- Admin `/installningar` tab `bokforing`: `BokforingCard` group
  "Biljetter" with the `ticketSales*` roles, shown only with `events`.
- Console: generic checkbox only.

Brand: a ticket-stub `Card surface="ticket"` (perforation, QR area) and a
status `Chip` are requested from the brand guardian; capacity uses `Bar
variant="meter"`, sales progress `Bar variant="progress"`.

## External dependencies

Stripe (existing), Turnstile (existing), Apple Wallet and Google Wallet
(new, optional: hidden without secrets; **human actions:** Apple
Developer Program membership and a Pass Type ID certificate, Google Wallet
API issuer account). Nothing new is mocked: pass generation is pure
signing, tested with a test certificate in `tests/fixtures/events_tickets/`.

## Privacy and GDPR

- Data: buyer name, email, optional phone; holder names on tickets;
  check-in times; order amounts. Legal basis: contract (art. 6(1)(b));
  bookkeeping (art. 6(1)(c)) for TX rows.
- Retention: contact fields on orders, tickets and transfers removed by the
  nightly job 24 months after the occurrence (contact rule); TX rows 7
  years; pending orders and transfers by TTL; scan data on the device
  deleted after sync.
- Erasure and export: `privacy.export` / `privacy.erase` by email hash
  across orders, tickets, transfers (names and emails removed; ticket
  validity and TX rows kept as bookkeeping records); `tenant.purge`
  deletes everything but TX rows get a 7-year `ttl` like gift cards.
- Wallet passes contain event title, time, place, ticket type, holder
  name and the QR, and nothing else (no email, phone or price); Google's
  copy has the holder name capped at 30 characters. Apple and Google
  receive what the pass shows (sub-processor note for the DPA list, human
  action).
- Storage registry: site-kit `TICKET_PURCHASE_KEY` = sessionStorage
  `booqy-ticket-purchase` (keeps `orderId` across 3-D Secure, nödvändig);
  admin `EVENT_SCAN_KEY_PREFIX` = IndexedDB `booqy-event-scan-<occurrenceId>`
  (guest list, scan key and queued check-ins for the door, nödvändig,
  removed after sync). No cookies.

## Swedish legal notes (human check)

- **VAT (accountant, flagged):** a ticket to a restaurant event is probably
  not "tillträde till evenemang" at 6 % (ML 9 kap., kulturella
  evenemang); a seat at a dinner is restaurant service at 12 % with alcohol
  at 25 % (BR-NFR-030), and a pure entrance fee (quiz night without food)
  may be 25 %. Advance payment: VAT falls due when the payment is received
  (ML 7 kap.). The feature lets the owner pick a rate per ticket type from
  an **accountant-approved list**; the list, the BAS accounts for
  `ticketSales` roles and whether a ticket with food and drink must be
  split into two lines on the receipt and entry are the accountant's call.
  The feature's STATUS row carries "needs accountant review" until signed
  off.
- Distance-sale withdrawal right: dated leisure events are exempt
  (distansavtalslagen 2 kap. 11 § 12); confirm the checkout text and the
  owner's refund policy wording.
- Receipt for online sales: confirm the ticket email meets the receipt
  requirement; kassaregisterlagen does not apply to distance sales
  (confirm).
- Resale at face value: no Swedish ticket-resale price law applies to the
  restaurant; confirm the terms text and that Booqy is not a marketplace
  under DSA art. 3 (the restaurant is the seller, Booqy processes).
- Alcohol: an event whose description is an alcohol promotion ("öl till
  halva priset") is the owner's responsibility (alkohollagen 7 kap.); the
  editor shows a reminder, nothing is blocked.

## Test plan

Two-tenant fixtures, `mock_aws()`, Stripe fake. Every route: happy path,
validation error, wrong role, foreign tenant 404, entitlement off refused,
idempotent retry.

| # | Validation | Wrong role | Foreign 404 | Off | Retry |
|---|---|---|---|---|---|
| K1 | bad status | staff other location 404 | LOC_B | 403 | n/a |
| K2 | capacity 0, price -1, series > 12 months | staff 403 | LOC_B | 403 | same eventId -> same event |
| K3 | n/a | staff gets no revenue | B's eventId | 403 | n/a |
| K4 | bad window | staff 403 | B's eventId | 403 | stale version 409 |
| K5 | n/a | staff 403 | B's eventId | 403 | second publish 200, no duplicate occurrences |
| K6 | bad VAT rate | staff 403 | B's eventId | 403 | same typeId -> one type |
| K7 | `has_sales` 409 | staff 403 | B's eventId | 403 | second delete 204 |
| K8 | capacity below sold 400 | staff 403 | B's occurrence | 403 | stale version 409 |
| K9 | n/a | staff 403 | B's occurrence | 403 | same jobId -> one job, every refund once |
| K10 | n/a | staff other location 404 | B's occurrence | 403 | n/a |
| K11 | bad sig -> `invalid`, 201 ids | staff other location 404 | B's ticket in A's batch -> `invalid` | 403 | same clientId -> `already` with the first time |
| K12 | bad cursor | staff 403 | B's eventId | 403 | n/a |
| K13 | n/a | staff 403 | B's ticketId | 403 | same txId -> one Stripe refund |
| K14 | n/a | staff 403 | B's jobId | 403 | n/a |
| K15-16 | n/a | n/a (public) | inactive tenant 404, draft event 404 | 404 | n/a |
| K17 | qty over max, bad email, no Turnstile, closed sales 409, sold out 409 | n/a | B's typeId at A's location 404 | 404 | same orderId -> same clientSecret, one hold |
| K18-19 | malformed token 404 | n/a | A's token at B 404 | 404 | n/a |
| K20 | transfer within 2 h 409, resale when allowed off 409 | n/a | foreign token 404 | 404 | same transferId -> one transfer |
| K21 | accepted twice 409 | n/a | foreign token 404 | 404 | second accept -> same ticketToken |
| K22 | n/a | n/a | foreign 404 | 404 | second delete 204 |

Plus: concurrent checkouts on the last seats (exactly `capacity` sold,
never more, per type too); hold expiry releases and a later checkout
succeeds; webhook replay issues once; foreign Stripe account event
ignored (`ignored:account_mismatch`); free tickets issue without Stripe;
series generation idempotent and resumable; mass refund resumable after a
crash with no double refund; resale: buyer pays, seller refunded once, old
ticket void and refused at scan, new valid; offline check-in sync with a
duplicate from two devices; Bokföring entry balanced with sale, refund and
resale and byte-identical SIE for tenants without events; insights money
stripped for staff; QR sig verified offline and online; code never stored
in plaintext; pass generation with the test certificate; two-tenant
isolation (A's scan key never validates B's ticket; A's guest list never
lists B); UI at mobile, tablet, desktop, light and dark, scanner tested
with a fixture image.

## Alternatives considered

- **Tickets as reservations with a price** in the reservation table: every
  reservation reader would need to learn ticket semantics; capacity per
  type does not fit. Rejected (ADR-F reasoning).
- **Stripe Checkout hosted page**: simpler, but it leaves the restaurant
  site and cannot hold tables. Rejected; PaymentIntent inline as for
  orders.
- **Per-ticket platform fee through Stripe application fees**: possible
  later; v1 keeps the business decision open [NEEDS YOUR OK].
- **Third-party scanning app**: offline needs make a web scanner in admin
  the simpler path; native apps are out of scope.

## Open questions

1. Seat-level (not table-level) assignment for concerts? Out of scope.
2. Should ticket buyers be offered the marketing opt-in checkbox like order
   checkout (`shared/MarketingConsent.tsx`)? Proposal: yes, same component.
3. Waitlist for sold-out occurrences (ADR-F pattern)? v2.
4. Door sales in Kassa (payment kind `ticket`, receipt): v1.1 after the
   control system voucher question (blocks E) is answered.
