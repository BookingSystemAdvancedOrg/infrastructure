# ADR-H: Personalliggare (electronic staff ledger)

**Status:** Proposed. **NEEDS LEGAL REVIEW** before any tenant uses it.
**Date:** 2026-11-01
**Deciders:** Owner (product), legal reviewer (Swedish tax law), orchestrator

> This feature must never be described as compliant, approved or certified
> ("uppfyller kraven", "godkänd", "certifierad", "Skatteverket-godkänd") in
> the admin app, guest sites, booqy.se, emails or sales material. Same rule
> as Kassa (BR-BOOQY-057). The UI says "Personalliggare (under granskning)"
> until the legal review is signed off.

## Context

Restaurants are among the businesses that must keep a personalliggare
(SFL 39 kap. 11 §): who works at the premises and when each shift starts and
ends, recorded as it happens, kept at the workplace and shown at once when
Skatteverket makes an unannounced visit (kontrollbesök). Booqy already has
staff users (`USER#<sub>/PROFILE`, tenant and location) and a proven
append-only pattern: the kassa journal is a separate table with an explicit
`Deny` resource policy on Update/Delete (`infrastructure/kassa/main.tf`) and
a SHA-256 hash chain whose head (`jseq`, `lastHash`) sits on the register row
(`shared/kassa.py` `entry_hash`, `verify_chain`).

## Decision

1. **Copy the kassa journal pattern.** Two tables (a justified exception to
   one table per feature, same as kassa): a mutable state table and an
   append-only ledger table with a `Deny` resource policy.
2. **Every check-in, check-out and correction is a new ledger record**, one
   transaction: Put ledger record (`attribute_not_exists`) + update the
   location's `HEAD` (condition `seq = :prev`, new `seq`, `lastHash`) + the
   presence pointer + an idempotency marker. A lost race retries server-side
   up to 3 times, then 409 `changed_retry`.
3. **Corrections never edit.** A correction record names `correctsSeq`, the
   corrected values and a required reason (5-300 chars). Readers show the
   corrected view with the original visible beside it.
4. **Persons, not only users.** Everyone who works must be in the ledger,
   including the owner and helpers without a Booqy login. Persons live in the
   state table with name and personal identity number, optionally linked to a
   user `sub`. Staff with a login check themselves in; the owner can record
   for anyone (recorded as "registrerad av").
5. **Time is server time.** `recordedAt` is always the server clock. A
   late or offline registration is a correction with `eventTime` and a reason,
   never a backdated check-in.
6. **Inspection view** ("Visa för Skatteverket") shows who is present now and
   the chosen day with full identity numbers. Staff can open it for their own
   location (the inspector must not wait for the owner); opening it appends a
   `system_note` record (`kind: inspection_view`) so access is traceable.
7. **Retention beyond offboarding.** The ledger is excluded from
   tenant-purge. Rows carry `ttl` = end of the 2nd calendar year after the
   record (to be confirmed by legal) and expire then. **Flag:** verify that
   the `Deny` resource policy does not block TTL deletes (TTL runs as the
   DynamoDB service, which should not be subject to it); if it does, add a
   yearly purge with a narrowly scoped policy exception, decided by a human.
   The state table (persons, head, presence) is purged on offboarding after a
   final export is offered; ledger records carry their own name and identity
   snapshot, so they stay readable.
8. **Export** for inspection and for the owner: CSV and JSON per location and
   date range, with the chain verification result. No official Skatteverket
   file format is assumed (verify).

## Data model

State table `<prefix>personalliggare` (PAY_PER_REQUEST, PITR, deletion
protection in prod, TTL `ttl`):

| PK | SK | Item |
|---|---|---|
| `TENANT#<t>` | `PERSON#<personId>` | `name`, `personalIdentity` (personnummer or samordningsnummer, checksum-validated), `userSub?`, `locationIds[]`, `active`, `version`, `createdAt` |
| `TENANT#<t>` | `USER#<sub>` | pointer to `personId` (one person per login) |
| `LOCATION#<l>` | `HEAD` | `tenantId`, `seq`, `lastHash`, `updatedAt` |
| `LOCATION#<l>` | `PRESENT#<personId>` | `checkInSeq`, `since` (open shift) |
| `LOCATION#<l>` | `REQ#<recordId>` | idempotency marker -> `seq`, `ttl` 7 days |

Ledger table `<prefix>personalliggare-ledger` (PAY_PER_REQUEST, PITR,
deletion protection in **all** environments, TTL `ttl`, resource policy
`DenyLedgerMutation`: UpdateItem, DeleteItem, BatchWriteItem,
PartiQLUpdate, PartiQLDelete for `Principal: *`):

| PK | SK | GSI `byDay` (PK `DAY#<l>#<yyyy-mm-dd>`, SK `seq`) |
|---|---|---|
| `LOCATION#<l>` | `SEQ#<000000000123>` | local day of `eventTime` |

Record: `tenantId`, `locationId`, `seq`, `recordId`, `kind`
(`check_in` | `check_out` | `correction` | `system_note`), `personId`,
`name`, `personalIdentity`, `employer` `{legalName, orgNumber}`,
`premises` (location name and address), `eventTime`, `recordedAt`,
`localTime` (Europe/Stockholm display), `recordedBy` `{sub, role}`,
`correctsSeq?`, `reason?`, `corrected?` `{kind, eventTime}`, `prevHash`,
`hash`, `ttl`. Hash: `shared.kassa.entry_hash`, imported read-only (it is
generic: sha256 of the sorted JSON without `hash`); no copy, no move.

## API routes

Errors `{error, code, field?}`. Staff are held to their assigned location.

| # | Method | Path | Auth | Role | Request -> response |
|---|---|---|---|---|---|
| 1 | GET | `/locations/{locationId}/personalliggare?day=` | JWT | owner, staff | -> `{present[], records[] (corrected view), me?}` (staff see names, not identity numbers) |
| 2 | POST | `/locations/{locationId}/personalliggare/check-in` | JWT | staff (self), owner (anyone) | `{recordId, personId?}` -> 201 record |
| 3 | POST | `/locations/{locationId}/personalliggare/check-out` | JWT | staff (self), owner (anyone) | `{recordId, personId?}` -> 201 record |
| 4 | POST | `/locations/{locationId}/personalliggare/corrections` | JWT | owner | `{recordId, correctsSeq?, personId, kind, eventTime, reason}` -> 201 record |
| 5 | GET | `/locations/{locationId}/personalliggare/inspection?day=` | JWT | owner, staff | -> full view incl. identity numbers; appends `inspection_view` |
| 6 | GET | `/locations/{locationId}/personalliggare/export?from&to&format=csv\|json` | JWT | owner | -> file + `chainOk`, `firstBadSeq?` |
| 7 | GET | `/tenant/personalliggare/persons` | JWT | owner | -> `{persons[]}` |
| 8 | PUT | `/tenant/personalliggare/persons/{personId}` | JWT | owner | `{name, personalIdentity, userSub?, locationIds[], active, version?}` -> person |
| 9 | GET | `/platform/tenants/{tenantId}/personalliggare/export?locationId&from&to` | operator JWT + `platform/admin` | platform_admin | -> CSV; audited `AUDIT#` row (works for offboarded tenants) |

Errors: 400 `invalid_personal_identity`, `reason_required`,
`invalid_event_time` (future, or older than the retention window),
`unsupported fields`; 403 `feature_not_in_plan`, `owner_only`; 404 foreign
location, person or seq; 409 `already_checked_in`, `not_checked_in`,
`no_person_for_user` (staff login not linked), `changed_retry`.

Idempotency: `recordId` (client ULID) writes `REQ#<recordId>` in the same
transaction; a retry returns the stored record with 200 and appends nothing.
Persons: client `personId`, conditional on `version`.

Route 9 is in the console API (`platform-tenants`), which forwards it to
`personalliggare` (op `personalliggare.export`, CONTRACTS.md 9.3) and
writes the audit row.

## Events

Bus `<prefix>booqy-events`, source `booqy.personalliggare`. Detail:
`tenantId`, `occurredAt`, `version: 1`, `locationId`, `seq`, `personId`.
**No name or identity number in events.**

| detail-type | extra detail |
|---|---|
| `Personalliggare.CheckedIn` | `eventTime` |
| `Personalliggare.CheckedOut` | `eventTime` |
| `Personalliggare.Corrected` | `correctsSeq`, `kind` |

No consumers planned.

## Terraform modules

- `infrastructure/personalliggare/`: both tables, `aws_dynamodb_resource_policy`
  on the ledger (same shape as `journal_append_only`), Lambda
  `personalliggare`, role (ledger: `PutItem`, `GetItem`, `Query` only;
  state: CRUD), Errors alarm.
- Root `personalliggare.tf`; routes
  `network/api-gateway/personalliggare-routes.tf`; route 9 in the console
  routes file.
- **IAM change to existing roles (call out):** `platform-tenants` and
  `tenant-purge` get `lambda:InvokeFunction` on `personalliggare:live`
  (forward and purge hooks), no table access.
- Purge (`tenant.purge` hook) deletes the **state** table rows only; the
  ledger is deliberately untouched (comment says why).

## Entitlement name

`personalliggare`. Off -> 403 `feature_not_in_plan`. Switching it off hides
the UI but never deletes or blocks reading the ledger for the owner through
route 6 (the duty to keep records outlives the subscription), so route 6
checks tenant and role but **not** the entitlement once records exist. This
is the one deliberate exception; tested.

## Plan availability (target)

starter and growth (a legal duty for most restaurants, not an upsell).
Run 0 ships `false` in every plan; enabled only after legal sign-off.

## UI placement

- Admin, group `passet` "Under passet": new item `/personalliggare`
  "Personalliggare" (owner and staff, feature `personalliggare`), with big
  "Checka in" / "Checka ut" buttons, "På plats nu", today's list, and
  "Visa för Skatteverket" (inspection view, full screen, high contrast).
- Same page, owner-only tabs "Personer" (persons and identity numbers) and
  "Rättelser" (correction form with required "Orsak") and "Exportera".
- A visible paper fallback note: "Fungerar inte appen? För liggaren på papper
  och lägg in rättelser efteråt." (wording for legal review).
- Console: tenant page, Activity or "Suspend or offboard" tab gets
  "Export staff ledger" (English).
- Storage registry: no new keys.

## External dependencies

None. Nothing mocked. Approval needed: **legal review** (human) before
enabling for any tenant.

## Privacy and GDPR

- Data: name, personnummer/samordningsnummer, work times, location, who
  recorded. Legal basis: art. 6(1)(c) legal obligation (SFL 39 kap.).
  Personnummer processing relies on dataskyddslagen 3 kap. 10 § (clearly
  justified by the legal duty).
- Access: identity numbers only in the inspection view, the export and the
  owner's persons tab; never in logs, events or error bodies (BR-NFR-012).
- Retention: per the legal minimum (assumed 2 years after the calendar year,
  verify), then TTL. Erasure requests during retention are refused under
  art. 17(3)(b); the person can get an art. 15 export from the owner.
  `guest-privacy` is not involved (staff, not guests).
- Offboarding: Booqy keeps the ledger as processor after the contract ends;
  the DPA needs a clause for this (human action).
- No browser storage, no cookies.

## Swedish legal notes (human check)

- SFL 39 kap. 11 §: confirm restaurant activity (serving food or drink for
  consumption on the premises, and catering) is in scope, and who counts as
  "verksam" (owner, family, unpaid helpers, staff hired from agencies).
- Skatteförfarandeförordningen 9 kap. and Skatteverket's föreskrifter
  (SKVFS 2015:6, as amended): required fields (identity, start and end time,
  employer org number), electronic ledger requirements (records cannot be
  changed, corrections traceable, available at once on site), and whether a
  premises/system notification to Skatteverket is required.
- Retention period of the ledger and of the system documentation.
- Kontrollbesök (SFL 42 kap.) and kontrollavgift (SFL 50 kap.): what an
  inspector must be able to see on the device, offline behaviour, and
  whether the paper fallback wording is acceptable.
- Whether staff checking in on their own phone satisfies "at the premises".

## Test plan

Two-tenant fixtures, `mock_aws()`. Each route: happy path, validation error,
wrong role, foreign tenant 404, entitlement off refused, idempotent retry.

| # | Validation | Wrong role | Foreign 404 | Off | Retry |
|---|---|---|---|---|---|
| 1 | bad day 400 | staff other location 404 | LOC_B | 403 | n/a |
| 2 | already checked in 409 | staff for another person 403 | LOC_B, person of B | 403 | same recordId -> same record, one seq |
| 3 | not checked in 409 | staff for another person 403 | LOC_B | 403 | same recordId -> same record |
| 4 | no reason 400; future time 400 | staff 403 | seq of LOC_B 404 | 403 | same recordId -> same record |
| 5 | bad day 400 | staff other location 404 | LOC_B | 403 | each call appends one note (by design) |
| 6 | from > to 400 | staff 403 | LOC_B | **allowed** when records exist (exception), 403 when none | n/a |
| 7 | n/a | staff 403 | only A's persons | 403 | n/a |
| 8 | bad personnummer checksum | staff 403 | personId of B 404 | 403 | stale version 409; same body -> same person |
| 9 | bad range 400 | tenant JWT 401/403 | unknown tenant 404 | n/a (operator) | n/a; audit row per call |

Plus: ledger role cannot Update/Delete (moto cannot enforce resource
policies, so a Terraform plan test asserts the policy, and an integration
check is listed as unverified in STATUS.md); chain verification detects a
tampered record; 20 concurrent check-ins on one location give 20 contiguous
seqs; correction view shows original and corrected values; tenant-purge
leaves the ledger untouched; copy check: a test greps admin, site-kit and
booqy-website sources for "uppfyller", "godkänd", "certifierad" near
"personalliggare" and fails. UI: light and dark, mobile, tablet, desktop.

## Alternatives considered

- **One table with a HEAD row**: the `Deny UpdateItem` policy would block the
  head update. Rejected (kassa learned the same).
- **QLDB**: discontinued by AWS. Rejected.
- **S3 Object Lock per day**: immutable, but no conditional sequence and
  awkward live reads. Could be added as a nightly signed copy later.
- **A shared tablet kiosk with PIN** instead of own logins: needs a new
  device auth model. Deferred; owner can record for anyone in v1.

## Open questions

1. Retention period and TTL-vs-Deny behaviour (see Decision 7).
2. Should the nightly job also write a signed daily digest to S3 Object Lock
   for extra tamper evidence?
3. Kiosk mode for staff without phones?
4. Should check-in be blocked outside opening hours or only warned?
