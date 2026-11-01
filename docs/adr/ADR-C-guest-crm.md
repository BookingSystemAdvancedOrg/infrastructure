# ADR-C: Guest CRM (unified guest profile and segments)

**Status:** Proposed
**Date:** 2026-11-01
**Deciders:** Owner (product), orchestrator (contracts); privacy review (human)
**Run:** built in Run 1; ADR-D (review requests) consumes its visit events in Run 2

## Context

Guest contact data sits as plain text on each reservation, order and
catering row (`customerName`, `customerEmail`, `customerPhone`), keyed by
location and date, so nothing answers "who is this guest, have they been
here before, what did they spend". Marketing already keeps a subscriber per
hashed email (`TENANT#<t>#SUB`, `SUB#<sha256(tenant|email)[:24]>`) with
`lastVisit` and audiences `all | recent | lapsed`. The consent log
(`shared/consent.py`) is append-only, keyed by
`subject = sha256(tenant|channel|identifier)[:32]`, and governs marketing
only (BR-NFR-009). Retention runs nightly (BR-NFR-008) and
`guest-privacy` exports and erases a guest (BR-REST-093).

## Decision

1. **One profile per guest per tenant**, identified by hashed contact
   identifiers. Each email and phone maps to a profile through an `IDENT`
   row whose hash is the **consent subject** (`consent.subject(tenant,
   channel, identifier)`), so consent lookups need no extra hashing. A
   booking with both email and phone links both to one profile; if they
   already point at two profiles, the older wins and the other is merged
   (conditional writes, history rows re-pointed, idempotent).
2. **No plaintext contact in the CRM.** The profile stores the latest
   display name and a `contactRef` (table + key of the newest source row).
   Email/phone are read live from that row when shown. When retention or
   erasure anonymises the source rows, the CRM shows no contact.
3. **Ingestion from DynamoDB Streams** of the reservation, order and
   catering-requests tables into a new `guest-crm-sync` Lambda (existing
   stream pattern, `ReportBatchItemFailures`, filter criteria on status
   changes). Counts: a booking counts as a visit when it becomes `arrived`;
   a no-show is counted separately; an order counts when completed/paid; a
   catering request when accepted or paid. Each source id is applied once
   (history row `attribute_not_exists`), so replays are safe. Sync writes
   only for tenants with `guestCrm` on, but emits `GuestVisit.Recorded` for
   tenants with `guestCrm` **or** `googleBusiness` on (ADR-D needs it).
4. **Backfill** on demand: owner presses "Bygg gästregistret" once; a
   self-re-invoking job walks the tenant's locations' source rows by key
   (no Scan), resumable by a cursor item.
5. **Segments are saved rules evaluated on demand** by a paginated Query of
   the tenant's profiles (expected under 50 000 per tenant): `lapsedDays`,
   `birthdayWithinDays`, `minSpendSek`, `minVisits`, `locationId`,
   `optedIn` (latest consent is a grant, `consent.may_send`). Profiles with
   `segmentsExcluded` (guest objected) never match.
6. **Export to marketing** writes an immutable export (subscriber ids of
   matching profiles that are **subscribed and consented**, chunked rows)
   and marketing gains audience `{type: "segment", exportId}`; marketing-send
   still calls `may_send` per recipient at send time. Non-consented guests
   can never be reached through the CRM.
7. **Staff see less**: staff get profiles for their own location's history,
   no amounts (BR-REST-084 rule); segments and exports are owner only.
8. **Erasure erases the profile**: `guest-privacy` erase calls the
   `privacy.erase` hook on `guest-crm`, which deletes IDENT, PROFILE, HIST
   and export rows referencing the guest; export (art. 15/20) includes the
   profile through `privacy.export`.

## Data model

Table `<prefix>guest-crm` (PAY_PER_REQUEST, PITR, deletion protection in
prod, TTL `ttl`). GSI `byLastSeen` (sparse, profiles only): `GSI1PK =
TENANT#<t>#GUESTS`, `GSI1SK = <lastSeenAt>#<guestId>`.

| PK | SK | Item |
|---|---|---|
| `TENANT#<t>` | `IDENT#<email\|sms>#<subject>` | `guestId` |
| `TENANT#<t>` | `PROFILE#<guestId>` | `name`, `contactRef{table, pk, sk}`, `identities[{channel, subject}]`, `firstSeenAt`, `lastSeenAt`, `visits`, `noShows`, `orders`, `cateringRequests`, `spendOre{bookingFees, orders, catering}`, `locations[]`, `birthday?` (`MM-DD`), `tags[]` (max 10, 24 chars), `note?` (max 300), `segmentsExcluded`, `subscriberId?`, `version`, `ttl` = `lastSeenAt` + 24 months |
| `TENANT#<t>` | `HIST#<guestId>#<at>#<kind>#<sourceId>` | `kind` (`booking` \| `order` \| `catering`), `locationId`, `date`, `status`, `partySize?`, `amountOre?`, `ttl` = source retention (bookings 395 days, orders/catering per `var.data_retention`) |
| `TENANT#<t>` | `SEGMENT#<segmentId>` | `name`, `rules{...}`, `version`, `createdBy`, `updatedAt` |
| `TENANT#<t>` | `EXPORT#<exportId>` | `segmentId`, `rules` (frozen), `count`, `chunks`, `createdBy`, `createdAt`, `ttl` = +90 days |
| `TENANT#<t>` | `EXPORT#<exportId>#<chunk:04d>` | `subscriberIds[]` (max 1 000), `ttl` = +90 days |
| `TENANT#<t>` | `BACKFILL` | `runId`, `cursor`, `status`, `counts` |

`guestId` is a ULID. History is keyed by guest so a profile reads in one
Query. No allergies or health data: the note field warns against it
(art. 9).

## API routes

Errors `{error, code, field?}`. Contact data goes in request bodies, never in
query strings.

| # | Method | Path | Auth | Role | Request -> response |
|---|---|---|---|---|---|
| 1 | GET | `/tenant/guests?cursor=&locationId=` | JWT | owner, staff (own location) | -> `{guests[{guestId, name, lastSeenAt, visits, returning}], cursor}` (newest first, `byLastSeen`) |
| 2 | POST | `/tenant/guests/search` | JWT | owner, staff | `{email?} \| {phone?} \| {name}` -> `{guests[]}` |
| 3 | GET | `/tenant/guests/{guestId}` | JWT | owner, staff | -> profile + `history[]` + `contact{email?, phone?}` + `consent{email, sms}`; staff: own location, no amounts |
| 4 | PATCH | `/tenant/guests/{guestId}` | JWT | owner | `{note?, tags?, birthday?, segmentsExcluded?, version}` -> profile |
| 5 | POST | `/locations/{locationId}/guests/lookup` | JWT | owner, staff | `{contacts[{key, email?, phone?}]}` (max 100) -> `{results{key: {status: new \| returning, visits, guestId?}}}` |
| 6 | GET | `/tenant/guest-segments` | JWT | owner | -> `{segments[]}` + starter templates |
| 7 | PUT | `/tenant/guest-segments/{segmentId}` | JWT | owner | `{name, rules, version?}` -> segment (create or update) |
| 8 | DELETE | `/tenant/guest-segments/{segmentId}` | JWT | owner | -> 204 |
| 9 | GET | `/tenant/guest-segments/{segmentId}/preview` | JWT | owner | -> `{total, reachable, sample[{guestId, name}]}` |
| 10 | POST | `/tenant/guest-segments/{segmentId}/exports` | JWT | owner | `{exportId}` -> `{exportId, count}` |
| 11 | POST | `/tenant/guests/rebuild` | JWT | owner | `{runId}` -> 202 `{status}` |

Errors: 400 `unsupported fields`, `invalid_rules`, `invalid_birthday`,
`note_too_long`, `too_many_contacts`; 403 `feature_not_in_plan`,
`owner_only`; 404 unknown or foreign guest, segment, location (staff at
another location also 404); 409 `changed_retry`, `rebuild_running`.

Idempotency: `segmentId`, `exportId`, `runId` are client ULIDs (conditional
Put; a retry returns the stored result, an export is never recomputed);
PATCH conditional on `version`; DELETE of a missing segment is 204.

## Events

Bus `<prefix>booqy-events`, source `booqy.guest-crm`. Every detail has
`tenantId`, `occurredAt`, `version: 1`. No names, emails or phones.

| detail-type | extra detail |
|---|---|
| `GuestVisit.Recorded` | `locationId`, `kind` (`booking` \| `order` \| `catering`), `sourceId`, `guestKey` (consent subject of the email, else of the phone), `channels[]` (`email`, `sms` present on the source), `contactRef{table, pk, sk}` (`table` is the logical name `reservation` \| `order` \| `catering`, never an environment table name), `returning`, `at` |
| `GuestProfile.Erased` | `guestId` |
| `GuestSegment.Exported` | `segmentId`, `exportId`, `count` |

`GuestVisit.Recorded` is emitted for arrived bookings, completed orders and
accepted/paid catering. ADR-D consumes it. ADR-F's `Waitlist.Converted` needs
no handling (the resulting booking is counted when it arrives).

## Terraform modules

- `infrastructure/guest-crm/`: table + GSI, Lambdas `guest-crm` (API +
  backfill) and `guest-crm-sync` (stream consumer), event source mappings on
  the reservation, order and catering-requests streams with filter criteria,
  DLQ on the shared dead-letter module, logs, alarms, roles. Root
  `guest-crm.tf`; routes `network/api-gateway/guest-crm-routes.tf`.
- IAM (new roles): stream read on the three tables; `GetItem` on source
  tables (contact read); Query on the reservation/order/catering tables
  for backfill; consent table Query; marketing table `GetItem` (subscriber);
  `events:PutEvents`; `lambda:InvokeFunction` on itself (backfill).
- **IAM change to existing roles (call out):** `guest-privacy`,
  `marketing` and `marketing-send` get `lambda:InvokeFunction` on
  `guest-crm:live` only (hooks `privacy.export`, `privacy.erase`,
  `marketing.segment`, CONTRACTS.md section 9); no CRM table access or
  table name on those roles.
- The module's `wiring` output lists the functions for `lambda_releases`,
  `tenant_aware_role_names`, `staff_check_role_names`; purge is the
  `tenant.purge` hook.

## Entitlement name

`guestCrm` (`entitlements.features.guestCrm`). Off -> 403
`feature_not_in_plan`. Not exposed in `/site-config` (no guest-facing part).

## Plan availability (target)

growth. Run 0 ships `false` in every plan.

## UI placement

- Admin, group `restaurangen`, new item `/gaster` "Gäster" (feature
  `guestCrm`; staff see it too): list (Senast här, Besök, Ny/Återkommande),
  search, profile drawer (historik, samtycke, anteckning, taggar, födelsedag,
  "Gästen vill inte ingå i utskick").
- `/marknadsforing?flik=mottagare` gains "Målgrupper" (segments, owner):
  rule builder ("Inte varit här på 90 dagar", "Fyller år inom 14 dagar",
  "Handlat för minst 2 000 kr", "Vill ha erbjudanden"), preview counts,
  "Använd i kampanj". `?flik=kampanjer` audience picker lists exports.
- `/bokningar` (group `passet`): "Ny gäst" / "Återkommande (4)" badge from
  route 5.
- Console: only the per-tenant feature checkbox.

## External dependencies

None new. Nothing mocked.

## Privacy and GDPR

- Data: name, hashed identifiers, references to source rows, visit/order
  history, spend, optional birthday, staff note and tags.
- Legal basis: art. 6(1)(f) legitimate interest (knowing returning guests,
  service quality, simple stats); marketing use only for guests with a
  logged consent (art. 6(1)(a) plus LEK). Profiling for direct marketing:
  absolute right to object (art. 21(3)) via `segmentsExcluded` and erase.
  The privacy notice template (`shared/privacy_notice.py`) gains a
  "Gästregister" paragraph (shared change, flagged).
- Retention: profile `ttl` 24 months after last activity (contact retention,
  BR-NFR-008); history rows follow source retention; exports 90 days.
  data-retention needs no change (TTL does it).
- Erase: erasing a guest erases IDENT, PROFILE, HIST and their ids in
  exports; logged as counts only (BR-NFR-012).
- Storage registry: no new browser storage; no cookies.

## Swedish legal notes (human check)

- Legitimate-interest assessment (intresseavvägning) for the guest register
  must be written by the restaurant (controller); provide a template.
- Marketing to segments: we rely on consent only; confirm we must not use
  the marknadsföringslagen 19 § existing-customer exception without the
  notice at collection that it requires.
- Birthday is stored only when the guest asked; confirm wording.

## Test plan

Two-tenant fixtures, `mock_aws()`. Every route: happy path, validation error,
wrong role, foreign tenant 404, entitlement off refused, idempotent retry.

| # | Validation | Wrong role | Foreign 404 | Off | Retry |
|---|---|---|---|---|---|
| 1 | bad cursor | staff sees own location only | n/a | 403 | n/a |
| 2 | two keys at once 400 | staff results own location only | B's email finds nothing | 403 | n/a |
| 3 | bad id | staff: no amounts, other location 404 | B's guestId 404 | 403 | n/a |
| 4 | birthday 02-30 | staff 403 | B's guestId 404 | 403 | stale version 409 |
| 5 | 101 contacts | staff other location 404 | LOC_B 404 | 403 | n/a |
| 6 | n/a | staff 403 | n/a | 403 | n/a |
| 7 | lapsedDays 3 | staff 403 | B's segmentId 404 | 403 | same id + body -> same segment |
| 8 | n/a | staff 403 | B's segment 404 | 403 | second delete 204 |
| 9 | n/a | staff 403 | B's segment 404 | 403 | n/a |
| 10 | unknown field | staff 403 | B's segment 404 | 403 | same exportId -> same count |
| 11 | n/a | staff 403 | n/a | 403 | same runId -> same job |

Plus: stream replay of the same record counts once; arrived -> undo ->
arrived counts once; email+phone merge idempotent; export excludes
unsubscribed, withdrawn and `segmentsExcluded`; marketing-send skips an
exported id whose consent was withdrawn after export; erase leaves no row
with the guest's ids; backfill resumable after timeout; no plaintext
email/phone in any CRM item (scan in test). **Two-tenant isolation test:**
the same email booked at TENANT_A and TENANT_B gives two unrelated profiles
(different subjects); A's routes never return B's profile, segment or export.

## Alternatives considered

- **Extend the marketing subscriber row into a profile**: only opted-in
  guests have one, so new vs returning would be wrong. Rejected.
- **Store plaintext contact on the profile**: easier display, but a second
  copy to retain and erase. Rejected for `contactRef`.
- **OpenSearch for search and segments**: unneeded at tens of thousands of
  profiles per tenant. Rejected.
- **Events from every source handler instead of streams**: touches many
  handlers. Rejected.

## Open questions

1. Stream consumer count: if the reservation or order stream already has two
   consumers, use an EventBridge Pipe instead of a third mapping.
2. Count a takeaway order without email/phone (Kassa receipts only)? v1: no.
3. High-value threshold default (2 000 SEK spend in 12 months?).
