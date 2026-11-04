# ADR-D: Google Business Profile (hours sync, review requests)

**Status:** Proposed
**Date:** 2026-11-01
**Deciders:** Owner (product), orchestrator (contracts); lawyer for the consent rule (human)
**Run:** built in Run 2; depends on ADR-C's `GuestVisit.Recorded` event

## Context

Restaurants keep opening hours and special days in Booqy (location
`businessHours`, `specialDays`: closed, other hours, or no online booking,
up to two years ahead, BR-REST-014) and again by hand in Google. Wrong hours
on Google cost guests. Reviews drive discovery, but asking every guest by
hand does not happen. Booqy sends transactional mail and SMS through
`functions/notification` (SES, SNS, dev outbox) and marketing only to
consented guests (`consent.may_send`, BR-REST-075). One-time timers use
EventBridge Scheduler created in code (`no-show-check`, `catering-lifecycle`).

## Decision

1. **Connect** with Google OAuth 2.0 (authorization code, offline access,
   scope `https://www.googleapis.com/auth/business.manage`), top-level
   redirect, server-side `state` bound to the owner `sub`. The refresh token
   goes to `booqy/<env>/google-business/<tenantId>`; the OAuth client is one
   platform secret `${prefix}google-business/app` (Terraform-created, value
   set by hand).
2. **Link** each Booqy location to one Google location
   (`locations/<id>` from the Account Management and Business Information
   APIs). One Google location links to at most one Booqy location.
3. **One-way sync, Booqy is the source.** Mapping: `businessHours` ->
   `regularHours.periods`; special day `closed` -> `specialHours` closed;
   `other hours` -> `specialHours` with periods; `no online booking` -> not
   sent (the restaurant is open); notes are not sent. Only the next 12
   months of special days are pushed. Sync = `locations.patch` with
   `updateMask=regularHours,specialHours`. An hourly scheduled job computes a
   hash of the mapped payload per linked location and calls Google only when
   it differs from `lastSyncHash`; "Synka nu" runs the same code for one
   location. Edits made in Google are overwritten (stated in the UI).
4. **Review requests** after an arrived booking or a completed order:
   consume `GuestVisit.Recorded` (ADR-C) from the bus. For each event with
   review requests enabled for the location and the source kind, create a
   one-time schedule at `at + delayMinutes` (default 120, range 30-4320),
   named `gbp-review-<kind>-<sourceId>` in group `<prefix>google-business`,
   `ActionAfterCompletion=DELETE`. At fire time the sender re-reads the
   source row through `contactRef` (an erased or anonymised guest has no
   contact and is skipped), checks the rules, and sends.
5. **Consent rule (decided):** a review request is treated as **direct
   marketing**. It is sent only when the latest consent record for that
   channel is a grant (`consent.may_send`), and every message carries the
   one-click unsubscribe / withdraw link. SMS only for guests with SMS
   consent (today the forms collect email consent only, so SMS is rare).
   This is the cautious reading; the soft opt-in exception is listed for the
   lawyer. Never send to a guest who has a later booking cancelled by the
   restaurant or a no-show on the same source.
6. **Frequency**: at most once per guest per `minDaysBetween` (default 90,
   range 30-365) per tenant, enforced by a conditional write on
   `REVSENT#<guestKey>` (`lastSentAt < now - N days`). No review gating: the
   same message goes to every eligible guest, with no rating question and no
   incentive (Google policy).
7. **Messages** are Swedish, from the restaurant's name, with the Google
   review link (`metadata.newReviewUri`) behind the existing signed
   marketing redirect (click counted, no open pixel). Email is sent via
   `shared/marketing_mail.py` (List-Unsubscribe); **SMS is sent via
   `notification:live`** (Lambda invoke of the notification alias,
   `InvocationType=Event`, kind `google-business.review-request`,
   `replyTo: null`, CONTRACTS.md 9.4), so the tenant sender, number
   prefixes, part counting and billing are notification's. `google-business-jobs`
   never publishes to SNS itself (built as decided on 2026-11-04, DECISIONS.md).
8. **Client port** `shared/google_business.py` (`GoogleBusiness`,
   `SimulatedGoogleBusiness`, env `GOOGLE_BUSINESS_CLIENT` from Terraform
   `google_business_client`), simulator refused in prod.

## Data model

Table `<prefix>google-business` (PAY_PER_REQUEST, PITR, deletion protection
in prod, TTL `ttl`). GSI `byLinked` (sparse, links only): `GSI1PK=LINKED`,
`GSI1SK=<tenantId>#<locationId>` for the hourly job.

| PK | SK | Item |
|---|---|---|
| `TENANT#<t>` | `CONNECTION` | `status` (`connected` \| `needs_reauth` \| `disconnected`), `googleAccount` (display name), `connectedAt`, `connectedBy`, `version` |
| `TENANT#<t>` | `OAUTH#<state>` | `sub`, `ttl` = +10 min |
| `TENANT#<t>` | `GLOC#<googleLocationId>` | `locationId` (uniqueness of the link) |
| `TENANT#<t>` | `REVSENT#<guestKey>` | `lastSentAt`, `channel`, `ttl` = `lastSentAt` + `minDaysBetween` + 2 days |
| `LOCATION#<l>` | `LINK` | `tenantId`, `googleLocation` (`locations/<id>`), `title`, `newReviewUri`, `lastSyncAt`, `lastSyncHash`, `syncStatus` (`ok` \| `error`), `lastError?{code}`, `version`; `GSI1PK/GSI1SK` |
| `LOCATION#<l>` | `REVIEWSETTINGS` | `tenantId`, `enabled`, `sources[]` (`booking`, `order`), `channels[]` (`email`, `sms`), `delayMinutes`, `minDaysBetween`, `version` |
| `LOCATION#<l>` | `REVJOB#<kind>#<sourceId>` | `tenantId`, `dueAt`, `status` (`scheduled` \| `sent` \| `skipped`), `reason?` (`no_consent` \| `recent` \| `no_contact` \| `disabled` \| `no_show`), `channel?`, `ttl` = +90 days |

`guestKey` is the consent subject from the event (no plaintext). `LOCATION#`
rows are read only after the location check.

## API routes

Errors `{error, code, field?}`. All routes **owner only**; staff 403
`owner_only`.

| # | Method | Path | Auth | Role | Request -> response |
|---|---|---|---|---|---|
| 1 | GET | `/tenant/google-business/connection` | JWT | owner | -> `{status, googleAccount?}` |
| 2 | POST | `/tenant/google-business/connection/start` | JWT | owner | `{}` -> `{authorizeUrl}` |
| 3 | POST | `/tenant/google-business/connection/callback` | JWT | owner | `{code, state}` -> connection |
| 4 | DELETE | `/tenant/google-business/connection` | JWT | owner | -> 204 (revokes, deletes secret, removes links, deletes pending schedules) |
| 5 | GET | `/tenant/google-business/locations` | JWT | owner | -> `{locations[{googleLocation, title, address, linkedTo?}]}` |
| 6 | GET | `/locations/{locationId}/google-business` | JWT | owner | -> `{link?, preview{regularHours, specialHours}, reviewSettings, stats{sent30d, skipped30d, clicks30d}}` |
| 7 | PUT | `/locations/{locationId}/google-business/link` | JWT | owner | `{googleLocation, version?}` -> link (first sync queued) |
| 8 | DELETE | `/locations/{locationId}/google-business/link` | JWT | owner | -> 204 |
| 9 | POST | `/locations/{locationId}/google-business/sync` | JWT | owner | `{}` -> `{syncStatus, changed, lastSyncAt}` |
| 10 | PUT | `/locations/{locationId}/google-business/review-settings` | JWT | owner | `{enabled, sources, channels, delayMinutes, minDaysBetween, version}` -> settings |
| 11 | GET | `/platform/tenants/{tenantId}/google-business` | operator | platform_admin | -> `{status, links[{locationId, title, syncStatus, lastSyncAt}]}` (console Integrations tab, forwarded by `platform-tenants`) |

Unsubscribe and click links reuse the existing marketing/consent public
routes; no new public route.

Errors: 400 `unsupported fields`, `invalid_state`, `invalid_delay`,
`invalid_days`, `invalid_channel`; 403 `feature_not_in_plan`, `owner_only`;
404 foreign or unknown location, unknown Google location; 409
`not_connected`, `already_linked` (Google location linked elsewhere),
`changed_retry`; 502 `google_unavailable` (with `retryAfter`).

Idempotency: link uses `GLOC#` uniqueness in one transaction (same link
again = 200); settings and link conditional on `version`; sync is naturally
idempotent (hash); schedule names are deterministic, so a replayed event
gets `ConflictException`, treated as success; the sender writes `REVJOB`
status with a condition `status = scheduled`, so a re-fired schedule never
sends twice (BR-GUEST-038).

## Events

Bus `<prefix>booqy-events`, source `booqy.google-business`. Every detail has
`tenantId`, `occurredAt`, `version: 1`.

| detail-type | extra detail |
|---|---|
| `GoogleConnection.Connected` | none |
| `GoogleConnection.Disconnected` | `reason` |
| `GoogleHours.Synced` | `locationId`, `changed` |
| `GoogleHours.SyncFailed` | `locationId`, `code` |
| `ReviewRequest.Sent` | `locationId`, `kind`, `sourceId`, `channel` |

Consumes `GuestVisit.Recorded` (source `booqy.guest-crm`) via an EventBridge
rule on the bus.

## Terraform modules

- `infrastructure/google-business/`: table + GSI, Lambdas `google-business`
  (API) and `google-business-jobs` (hourly sync, bus rule target, review
  sender), Scheduler group `<prefix>google-business` + invoke role, hourly
  schedule, bus rule on `GuestVisit.Recorded` with DLQ, logs, alarms, roles.
  Root `google-business.tf` passes `var.google_business_client` (declared
  by Run 0 in `external-clients.tf`); routes
  `network/api-gateway/google-business-routes.tf`.
- **IAM (new roles; call out):** Secrets Manager create/put/get/delete on
  `booqy/<env>/google-business/*`; get on the app secret; location table
  `GetItem`; reservation/order `GetItem` (contact via `contactRef`); consent
  Query; SES send (sender identity) for the review email;
  `lambda:InvokeFunction` on `notification:live` for the review SMS (no
  `sns:Publish`); marketing link-key secret read (signed redirect);
  `scheduler:CreateSchedule/DeleteSchedule` on its group, `iam:PassRole` on
  the invoke role; `events:PutEvents`.
- The module's `wiring` output lists the functions; purge is the
  `tenant.purge` hook (rows, per-tenant secret, pending schedules).

## Entitlement name

`googleBusiness` (`entitlements.features.googleBusiness`). Off -> 403
`feature_not_in_plan`; the jobs skip tenants without it.

## Plan availability (target)

starter and growth (hours sync is basic hygiene; review requests ride on it).
Run 0 ships `false` in every plan.

## UI placement

- Admin, `/installningar`, section verksamhet, owner card "Google-profil":
  "Koppla Google", pick Google location per restaurant, sync status
  ("Synkat 14:05"), "Synka nu", preview of what Google will show, notice
  "Ändringar i Google skrivs över av Booqy".
- Admin, `/marknadsforing?flik=omdomen` (new tab "Omdömen"): review request
  settings per location (på/av, efter bokning / beställning, fördröjning,
  "högst en gång per 90 dagar", e-post/SMS), sent/skipped/clicks.
- Console: TenantPage "Integrations" tab (shared with ADR-A) shows
  connection and sync status.

## External dependencies

Google Business Profile APIs (Account Management, Business Information),
mocked in Runs 1-2. **Human actions:** request GBP API access for Booqy's
Google Cloud project (quota is 0 until approved); OAuth consent screen
verification for the sensitive `business.manage` scope. SES existing; SMS
through the existing notification Lambda.

## Privacy and GDPR

- Data: no guest data goes to Google. Booqy stores hashed guest keys,
  job status and send time; contact is read from the source row at send.
- Legal basis: review request as marketing with consent (art. 6(1)(a),
  LEK/MFL); hours sync is restaurant data (contract).
- Retention: `REVJOB` 90 days, `REVSENT` until the frequency window ends.
- Erase: `guest-privacy` erase calls the `privacy.erase` hook on
  `google-business`, which deletes `REVSENT#<subject>` rows and pending
  `REVJOB` (and their schedules); the sender also skips anonymised rows.
- Storage registry: none; no cookies, no tracking pixel in the email.

## Swedish legal notes (human check)

- Is a post-visit review request marketing (MFL 19 §, LEK 6 kap. 18 §)? We
  assume yes and require consent. Ask whether the existing-customer exception
  (contact collected at sale, notice and opt-out at collection) may be used
  if the booking form adds that notice.
- Konsumentverket guidance on reviews (no selective asking, no incentives);
  Omnibus rules on fake reviews.

## Test plan

Two-tenant fixtures, `mock_aws()`, `SimulatedGoogleBusiness`. Every route:
happy path, validation error, wrong role, foreign tenant 404, entitlement off
refused, idempotent retry.

| # | Validation | Wrong role | Foreign 404 | Off | Retry |
|---|---|---|---|---|---|
| 1 | n/a | staff 403 | own tenant only | 403 | n/a |
| 2 | unknown field | staff 403 | n/a | 403 | new state each call |
| 3 | bad state 400 | staff 403 | B's state 400 | 403 | reused state 400 |
| 4 | n/a | staff 403 | n/a | 403 | second call 204 |
| 5 | not connected 409 | staff 403 | n/a | 403 | n/a |
| 6 | n/a | staff 403 | LOC_B 404 | 403 | n/a |
| 7 | unknown Google location 404 | staff 403 | LOC_B 404 | 403 | same link -> 200 |
| 8 | n/a | staff 403 | LOC_B 404 | 403 | second delete 204 |
| 9 | not linked 409 | staff 403 | LOC_B 404 | 403 | second sync `changed=false`, no API call |
| 10 | delay 10, days 400, channel fax | staff 403 | LOC_B 404 | 403 | stale version 409 |

Plus: mapping tests (closed, other hours, no-online-booking ignored,
overnight hours, 12-month cut); hourly job idempotent and resumable (no call
when hash equal; continues after a failed location); review flow: no
consent -> skipped, recent -> skipped, erased guest -> skipped, replayed
event -> one schedule, re-fired schedule -> one message; simulator refused
in prod. **Two-tenant isolation test:** A cannot link to or read LOC_B; the
same guest at A and B has two `REVSENT` keys; A's job never reads B's
secret or B's source rows.

## Alternatives considered

- **Two-way sync** (import Google edits): conflicts and a second source of
  truth. Rejected.
- **Transactional framing without consent**: more reach, legal risk.
  Rejected until the lawyer answers.
- **Own stream consumer on reservations/orders**: duplicates ADR-C's
  ingestion and adds stream consumers. Rejected for the bus event.
- **Polling sweep for due review jobs** instead of one-time schedules:
  needs a due-time GSI and a frequent job. Rejected; the Scheduler pattern
  exists.

## Open questions

1. Reply to reviews from admin (Run 3 or later)?
2. SMS cost for review requests: billed like other SMS (BR-BOOQY-028)?
3. Push special days beyond 12 months?
