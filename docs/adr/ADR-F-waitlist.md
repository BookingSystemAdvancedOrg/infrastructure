# ADR-F: Waitlist and walk-in queue

**Status:** Proposed
**Date:** 2026-11-01
**Deciders:** Owner (product), orchestrator (contracts)
**Run:** built in Run 2, against the Run 0 contract

## Context

When a location is full, guests leave and walk-ins wait at the door with no
record. Staff need one queue per location and day, guests need to join from
the restaurant site, and a freed table must reach the next guest fast without
ever double-booking. The codebase already has the hard part:
`shared/reservations.py` claims `SLOT#<date>#<s-e>#<table>` rows plus a
`LOCK#<date>#<table>` version bump in one `transact_write_items`, and guest
table holds (`HELD` reservations with `holdExpiresAt` on the slot rows, made
by `create-pending-reservation`) turn into bookings with `keep_hold_items`.
SMS is sent by `functions/notification` from DynamoDB streams (SNS, Nordic
prefixes only, parts counted for billing, dev outbox copy).

## Decision

1. **The queue is its own table**, one entry per guest per location and day.
   Same-day only in v1 (today in the location's time zone).
2. **An offer is an existing table hold.** "Erbjud bord" creates a `HELD`
   reservation through the same `hold_items` path guests use, with
   `holdExpiresAt = now + holdMinutes` (default 10, range 5-30). The table is
   therefore blocked for everyone else by the existing occupancy rows, and an
   expired hold is already taken over by the existing rule
   (`holdExpiresAt <= :now`). No new locking code.
3. **Conversion is one transaction**: `keep_hold_items` + the reservation
   update from `HELD` to `reserved` (or `arrived` when seated at the door) +
   the waitlist entry update (condition `status = offered AND version = :v`).
   A lost race returns 409 `hold_expired` / `changed_retry`, exactly like the
   guest hold flow.
4. **"A table frees" is staff-confirmed.** The queue response carries
   `suggestions` (first waiting party that fits a table free now, computed with
   the same availability code). Staff press "Erbjud"; no automatic offers in
   v1, because a wrong auto-offer at a busy door costs more than one tap.
5. **SMS goes through `notification`**: after the write, the waitlist
   Lambda records `notice{kind, at}` on the entry with a condition and
   invokes `notification:live` (InvocationType Event) with the rendered
   Swedish text (CONTRACTS.md 9.4, entry built in Run 0). This keeps one
   place for SNS, prefixes, the sender name, part counting (BR-BOOQY-028)
   and the dev outbox, with no stream and no new permission on
   notification. A failed invoke leaves the entry without `notice.sentAt`
   so staff see "Sms ej skickat".
6. **Expiry** uses a one-time EventBridge Scheduler schedule per offer
   (`waitlist-offer-<entryId>`, group `<prefix>waitlist`), the
   `no-show-check` pattern. It sets the entry to `expired` (conditional) and
   releases the hold with `release_items`. Reads also treat a passed
   `offer.expiresAt` as expired, so a late or missing timer changes nothing.

## Data model

Table `<prefix>waitlist` (PAY_PER_REQUEST, PITR, deletion protection in prod,
TTL `ttl`, no stream). Route 6 also mirrors `publicJoin` onto the location
row as `waitlist = {publicJoin}` (UpdateItem limited to that attribute) for
`/site-config`.

| PK | SK | Item |
|---|---|---|
| `LOCATION#<l>` | `ENTRY#<yyyy-mm-dd>#<entryId>` | queue entry |
| `LOCATION#<l>` | `SETTINGS` | `enabled`, `holdMinutes` (5-30, default 10), `maxWaiting` (1-200, default 50), `publicJoin` (bool), `version` |

Entry: `tenantId`, `locationId`, `entryId` (client ULID), `date`,
`partySize` (1-20), `name` (1-80), `phone` (E.164, required for SMS),
`email?`, `note?` (max 200), `source` (`site` | `staff`),
`status` (`waiting` | `offered` | `seated` | `booked` | `expired` |
`left` | `removed`), `joinedAt`, `wantFrom?`/`wantUntil?` (HH:MM),
`offer?` `{reservationId, tableIds, startTime, endTime, expiresAt, offeredBy}`,
`reservationId?` (after conversion), `manageTokenHash`, `notice?`
`{kind: joined|offered|expired, at}`, `version`, `history[]` (who, when,
what, like BR-REST-028), `ttl` = end of `date` + 30 days.

Access: staff list = Query `PK=LOCATION#<l>`, `begins_with(SK, ENTRY#<date>)`;
guest = GetItem from the HMAC token (`shared/manage_link.py` style, token
carries locationId, date, entryId). No GSI. Position = order of `joinedAt`
among `waiting`.

## API routes

Errors are `{error, code, field?}`. Staff are held to their assigned
location (`staff_location`).

| # | Method | Path | Auth | Role | Request -> response |
|---|---|---|---|---|---|
| 1 | GET | `/locations/{locationId}/waitlist?date=` | JWT | owner, staff | -> `{settings, entries[], suggestions[{entryId, tableIds, startTime}]}` |
| 2 | POST | `/locations/{locationId}/waitlist` | JWT | owner, staff | `{entryId, name, partySize, phone?, note?}` -> 201 entry (walk-in) |
| 3 | POST | `/locations/{locationId}/waitlist/{entryId}/offer` | JWT | owner, staff | `{tableIds, startTime, version}` -> entry with `offer`; 409 `table_taken` |
| 4 | POST | `/locations/{locationId}/waitlist/{entryId}/seat` | JWT | owner, staff | `{tableIds?, version}` -> `{entry, reservationId}` (converts, status arrived) |
| 5 | POST | `/locations/{locationId}/waitlist/{entryId}/remove` | JWT | owner, staff | `{version, reason?}` -> entry; releases any hold |
| 6 | PUT | `/locations/{locationId}/waitlist/settings` | JWT | owner | settings body + `version` -> settings |
| 7 | POST | `/public/locations/{locationId}/waitlist` | Turnstile + request guard | guest | `{entryId, name, partySize, phone, email?, wantFrom?, wantUntil?, turnstileToken}` -> 201 `{token, position}` |
| 8 | GET | `/public/waitlist/{token}` | token | guest | -> `{status, position, offer?{startTime, expiresAt}, locationName}` |
| 9 | POST | `/public/waitlist/{token}/accept` | token | guest | `{}` -> `{reservationId, manageToken}`; 409 `hold_expired` |
| 10 | POST | `/public/waitlist/{token}/leave` | token | guest | `{}` -> 204 (idempotent) |

Errors: 400 `invalid_party_size`, `invalid_phone`, `unsupported fields`;
403 `feature_not_in_plan` (JWT), `owner_only`; 404 unknown/foreign location
or entry, bad token, feature off (public), `publicJoin` off; 409
`queue_full`, `already_queued` (same phone today), `changed_retry`,
`table_taken`, `hold_expired`, `invalid_state`.

Idempotency: `entryId` is client-supplied (Put with
`attribute_not_exists`; a retry with the same body returns the stored entry);
offer/seat/remove are conditional on `version` and `status`, and a retry
after success returns the current entry; accept on a `booked` entry returns
the same `reservationId`.

## Events

Bus `<prefix>booqy-events`, source `booqy.waitlist`. Every detail has
`tenantId`, `occurredAt`, `version: 1`, `locationId`, `entryId`, `date`.
No name or phone in events.

| detail-type | extra detail |
|---|---|
| `Waitlist.Joined` | `source`, `partySize` |
| `Waitlist.TableOffered` | `reservationId`, `tableIds`, `expiresAt` |
| `Waitlist.Converted` | `reservationId`, `how` (`accepted` \| `seated`) |
| `Waitlist.OfferExpired` | `reservationId` |
| `Waitlist.Left` | `by` (`guest` \| `staff`) |

Published by the waitlist Lambda after the write succeeds (best effort,
logged metric on failure); no consumer in Run 2 needs exactly-once. Guest
CRM (ADR-C) does not consume them (the resulting booking is counted when the
guest arrives).

## Terraform modules

- `infrastructure/waitlist/` (`main.tf`, `variables.tf`, `outputs.tf`):
  table, Lambda `waitlist` (image, arm64, `live` alias, 30-day logs, Errors
  alarm), role, scheduler group `<prefix>waitlist` and invoke role.
- Root `waitlist.tf`; routes `network/api-gateway/waitlist-routes.tf`.
- IAM (new role only): reservation and slot-occupancy item actions the same
  as `create-pending-reservation`, waitlist table CRUD, location/tenant
  read (tenant-context), `scheduler:CreateSchedule/DeleteSchedule` on its
  group, `iam:PassRole` for the invoke role, `events:PutEvents` on the bus,
  Turnstile and link-signing secret ARNs.
- **IAM change to existing roles (call out):** `guest-privacy` and
  `tenant-purge` get `lambda:InvokeFunction` on `waitlist:live` (hooks).
  The new waitlist role gets invoke on `notification:live`; notification
  gets nothing new.
- The module's `wiring` output lists the function for `lambda_releases`,
  `tenant_aware_role_names`, `staff_check_role_names`; purge is the
  `tenant.purge` hook.

## Entitlement name

`waitlist` (`entitlements.features.waitlist`). Off -> 403
`feature_not_in_plan` on JWT routes, 404 on public routes. `/site-config`
exposes `tenant.features.waitlist` and per location `waitlist.publicJoin`.

## Plan availability (target)

starter and growth. Run 0 ships `false` in every plan.

## UI placement

- Admin, group `passet` "Under passet", `/bokningar`: a "Kö" panel next to
  the day list with a count badge, the suggestion line ("Bord 4 är ledigt
  för Sara, 2 pers.") and actions "Erbjud bord", "Placera nu", "Ta bort".
  The table picker reuses the read-only floor plan from `layout-editor`
  (the "Layout" part of this feature; no edits to the editor).
- Admin, `/installningar`, section verksamhet: owner card "Kö" (på/av,
  hålltid, max antal, kö från hemsidan).
- Guest site: `/ko` (join, linked from `boka-bord` when no times are free:
  "Fullt just nu? Ställ dig i kö") and `/ko#<token>` (status, "Ta bordet",
  "Lämna kön"), site-kit feature folder `ko`, lazy in `sitePages`.
- Console: only the generic per-tenant feature checkbox (Run 0).

## External dependencies

SNS SMS (existing), Turnstile (existing). Nothing new, nothing mocked, no
approval needed.

## Privacy and GDPR

- Data: name, phone, optional email and note, party size. Legal basis:
  art. 6(1)(b) (the guest asked to be queued). The SMS is a service
  message, never marketing; the consent log is not used (BR-NFR-009).
- Retention: `ttl` 30 days after the day; the reservation made from an
  entry follows the existing booking retention (BR-NFR-008).
- Erasure: `guest-privacy` export and erase reach waitlist entries by
  phone/email through the `privacy.export` / `privacy.erase` hooks (the
  30-day TTL bounds the gap); tenant-purge deletes the rows through the
  `tenant.purge` hook.
- Storage registry (site-kit `storageRegistry.ts`): new
  `WAITLIST_TOKEN_PREFIX` = localStorage `booqy-waitlist-<locationId>`,
  category nödvändig, holds the guest's queue token until the day ends.
  No cookies.

## Swedish legal notes (human check)

- SMS with no marketing content needs no marketing consent (marknadsföringslagen
  19 §, LEK); confirm the offer text stays purely informational.
- Confirm the privacy notice on the site lists the queue as a purpose.

## Test plan

Two-tenant fixtures (`tests/tenant_support.py`, `TENANT_A` / `TENANT_B`) in
`mock_aws()`. Each route gets: happy path, validation error, wrong role,
foreign tenant 404, entitlement off refused, idempotent retry.

| # | Validation | Wrong role | Foreign 404 | Off | Retry |
|---|---|---|---|---|---|
| 1 | bad date 400 | staff at other location 404 | LOC_B from A | 403 | n/a (GET) |
| 2 | party 0 / 21 | staff other location | LOC_B | 403 | same entryId -> same entry |
| 3 | table of other location | staff other location | entry of B | 403 | second offer -> current entry, one hold |
| 4 | stale version 409 | staff other location | entry of B | 403 | second seat -> same reservationId |
| 5 | unknown field 400 | staff other location | entry of B | 403 | second remove -> 200 same |
| 6 | holdMinutes 3 | staff -> 403 `owner_only` | LOC_B | 403 | same version twice -> 409 then GET |
| 7 | bad phone, no Turnstile | n/a (public) | location of inactive tenant 404 | 404 | same entryId -> same token |
| 8 | malformed token 404 | n/a | token for B's entry signed with A data 404 | 404 | n/a |
| 9 | accept when waiting 409 | n/a | foreign token 404 | 404 | second accept -> same reservationId |
| 10 | n/a | n/a | foreign token 404 | 404 | second leave 204 |

Plus: race test (two offers on one table, one accept vs one walk-in booking:
exactly one wins, the other 409); accept after `expiresAt` -> 409 and the
table is bookable; expiry timer idempotent (run twice) and resumable (timer
after accept is a no-op); stream record produces exactly one SMS notice;
availability for guests unchanged while an offer is open; site and admin UI
at mobile, tablet, desktop, light and dark. "Stream record produces exactly
one SMS" reads: one accepted state change gives exactly one notification
invoke (retry of the same call gives none).

## Alternatives considered

- **Waitlist rows in the reservation table** (`WAITING` status): fewer
  tables, but every reservation reader (day list, insights, reminders,
  retention) would have to learn to skip them. Rejected.
- **Automatic offers on cancel/no-show** via a new reservation event:
  needs a reservation event source that does not exist and risks wrong
  offers. Deferred to a later version.
- **Own SMS sender in the waitlist Lambda**: duplicates prefixes, part
  counting and outbox. Rejected.

## Open questions

1. Future-day waitlist (join for Saturday)? v1 is same-day only.
2. Should an offered guest without a phone (staff entry) be called by staff
   only? v1: offer works, no SMS, staff tell the guest.
3. Does a card guarantee apply when a waitlist entry becomes a booking? v1:
   no guarantee for waitlist conversions; owner to confirm.
