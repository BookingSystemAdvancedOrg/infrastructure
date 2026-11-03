# Decisions log

Small, dated decisions that settle a contradiction or a defect between the
ADRs, CONTRACTS.md and the code, without a full ADR of their own. Newest
last. Each entry names what was contradictory, what was decided, why, and
which files were changed so the sources agree again.

## 2026-11-02: `insights.events` hook gate is "events on or ever on", not owner-only

**Contradiction.** CONTRACTS.md section 17 (the exact `booqy.yaml`
additions) listed `insights.events` with `gate: on_owner`, while 8.2 and
9.2 said the hook is called when `events` is on or ever on and that the
slot `statistik.events` has `ownerOnly: false` with the server stripping
money for staff. `contracts/booqy.yaml` on `build/run-0-addendum-kl`
already carried `gate: events on or ever on`.

**Decision.** Staff see the Statistik events slot with money removed;
the hook is gated on `events` on or ever on (`ever_on`), and
`without_money` strips `revenueOre` for non-owner callers. Section 17 is
corrected to `ever_on`; 8.2, 9.2 and the YAML are unchanged.

**Reason.** Occurrences, tickets sold and check-ins are operational
figures the floor staff need on the day (ADR-K section 10); only revenue
is owner-only, and the existing `without_money` path already handles
that split for every other insight. "Ever on" keeps history visible
after the feature is turned off, like `accounting.events`. An owner-only
gate would have hidden the whole slot from staff, which contradicts the
slot's `ownerOnly: false` and the placement contract in 8.2.

**Files.** `docs/build/CONTRACTS.md` section 17 (hooks block).

## 2026-11-02: console slot `settings.phoneAgent` has `feature: null`

**Defect.** Section 17 and `contracts/booqy.yaml` gave the console slot
`settings.phoneAgent` `feature: phoneAgent`. The console Settings page is
platform-wide and renders its slots without a tenant feature set, so the
card would never have shown; `settings.metaAds` already has
`feature: null` for the same reason.

**Decision.** `settings.phoneAgent: {feature: null, ownerOnly: false,
host: SettingsPage}`, the same as `settings.metaAds`. The five generated
contract files are regenerated; the console slot test asserts the slot
always shows.

**Files.** `application/contracts/booqy.yaml`, the five generated targets
of CONTRACTS.md 1.2, `docs/build/CONTRACTS.md` section 17,
`booqy-console/web/src/slots.test.tsx`.

## 2026-11-03: guest-crm-sync is the last direct DynamoDB stream reader

**Contradiction.** Run 1 feature C added `guest-crm-sync` as a third reader
on the reservation and catering-request streams and a fourth on the order
stream (`guest-crm/main.tf`, `aws_lambda_event_source_mapping.source`).
DynamoDB Streams throttles GetRecords above two concurrent readers per
shard, so every extra reader slows all of them (print-jobs already alarms on
IteratorAge for this). An EventBridge Pipe (ADR-C open question 1) is also
a stream reader, so it does not help.

**Decision.** `guest-crm-sync` is the LAST feature that reads a source
table's stream directly. It ships with an IteratorAge alarm
(`guest-crm-sync-iterator-age`, 5 minutes for 5 minutes) so throttling shows
up. Before features D or F (Run 2) add any consumer of these tables, build
one stream-fanout consumer per source stream that publishes the changes to
the `booqy-events` bus; new features (and, later, the existing readers)
subscribe to the bus instead of the stream.

**Reason.** Readers past two per shard add throttling for every reader,
and paid-order printing is on the same stream. One fan-out consumer keeps
each stream at a fixed reader count however many features listen, and the
bus already carries the domain events with per-rule DLQs.

**Files.** `guest-crm/main.tf` (alarm `sync_iterator_age`); this entry.
The fan-out consumer itself is Run 2 work for the orchestrator.

## 2026-11-03: notification kind `meta-ads.cap-warning`

**Contradiction.** ADR-A decision 6 says the nightly insights job emails the
owner at 80 % of the monthly cap, and `meta-ads-jobs` sends it through
`notification:live` with `kind: meta-ads.cap-warning` (`_warn_owner`, once
per month via `SPEND#<month>.warnedAt`; the module grants the invoke).
CONTRACTS.md 9.4 listed only the gift-card, waitlist and addendum kinds, so
the billing kind the notification Lambda sees was undocumented.

**Decision.** `meta-ads.cap-warning` (email to every active owner at 80 %)
is a contract kind in 9.4; section 14 names meta-ads-jobs among the callers
of `notification:live`.

**Files.** `docs/build/CONTRACTS.md` 9.4 and 14.

## 2026-11-03: A8 `assets_missing` covers a location without a stored `position`

**Contradiction.** A8 needs the location's geocode for the ad set's radius.
The code refuses a location whose row has no `cateringOrigin.position` with
409 `assets_missing` (admin copy already says the address is saved under
Catering > Leverans), but CONTRACTS.md 6.A listed `assets_missing` only as
the Meta-asset case.

**Decision.** 409 `assets_missing` also means the location has no stored
position; the contract names the field `position` and the response carries
`field: "position"` in that case (the ad account, Page and dish image cases
carry no `field`). The handler sets the field; the A8 test asserts it.

**Reason.** One code keeps the admin's existing mapping; the `field` lets
the UI point at the location settings instead of Meta.

**Files.** `docs/build/CONTRACTS.md` 6.A (A8), `docs/adr/ADR-A-meta-ads.md`
test row 8, `application/functions/meta-ads/app.py`,
`application/docs/openapi/meta-ads.yaml`, `application/tests/test_meta_ads.py`.

## 2026-11-03: ADR-B test row 4 "contrast 3:1 -> 400" is unreachable

**Contradiction.** ADR-B decision 3 nudges every theme pair with site-kit's
`accentPair` before checking contrast. The nudge walks towards near-black
or white until the text contrast is >= 4.5:1 and reaches it at t = 1.0 for
any valid hex colour, and the text colour is then chosen for the nudged
accent, so `contrast_report` can never see a pair under 4.5:1. The test
plan row "contrast 3:1" (a 400) could not be written.

**Decision.** Row 4 reads "a 3:1 theme colour is nudged to >= 4.5:1 and
recorded in `contrast[]` (no 400)". `contrast_too_low` stays in B4 and in
the ADR as a safety net (the code path exists and is tested by stubbing
`accent_pair`), marked as such in CONTRACTS.md 6.B.

**Files.** `docs/adr/ADR-B-site-builder.md` test plan,
`docs/build/CONTRACTS.md` 6.B (B4).

## 2026-11-03: B5 `error.code` gains `start_failed`

**Defect.** Review F2 made B4/B7 mark the `PUBLISH#` row `failed` with
`error: {code: start_failed}` and release the tenant lock when
StartExecution fails, and a retry with the same `publishId` starts it
again. B5's contract (`error?{code, field}`) only knew the Validate codes
and always implied a `field`.

**Decision.** B5 returns `error?{code, field?}`; `code` is a B2/B4
validation code (with `field`) or `start_failed` (no `field`). B4 and B7
idempotency columns say the retry restarts a `start_failed` row.

**Files.** `docs/build/CONTRACTS.md` 6.B (B4, B5, B7),
`docs/adr/ADR-B-site-builder.md` errors and test rows 4-5,
`application/docs/openapi/site-builder.yaml`.

## 2026-11-03: reserved page slugs are 400 `schema_invalid` at `/pages/<i>/slug`

**Defect.** Review F8: a builder page whose slug is a first path segment the
customer app routes itself (`meny`, `presentkort`, `ko`, ...) or an S3
prefix under `sites/<t>/` (`v`, `releases`, `preview`, `assets`) would never
be served, so the code refuses it on save and publish. 8.4 only said the
builder catch-all must not shadow the site-kit pages; the error was not in
the contract.

**Decision.** Documented in CONTRACTS.md 6.B: 400 `schema_invalid`,
`field` = `/pages/<i>/slug`, the same as a duplicate slug. The single list
is `RESERVED_SLUGS` in `application/shared/features/site_builder/__init__.py`,
with a test that it covers every `path="..."` of
`customer-front-end/src/App.tsx`; a new customer-app route is added there
first. No new error code: the admin already renders `schema_invalid` with
the pointer.

**Files.** `docs/build/CONTRACTS.md` 6.B, `docs/adr/ADR-B-site-builder.md`
errors, `application/docs/openapi/site-builder.yaml` (400 description).

## 2026-11-03: A9 never returns `cursor`

**Contradiction.** CONTRACTS.md 6.A gave A9 `{campaigns[], cursor?}`;
ADR-A route 9 gave `{campaigns[]}`. Review F19 made the handler omit the
key (it had sent `cursor: null`), and the OpenAPI fragment still documented
a nullable `cursor` and a `cursor` query parameter the handler rejects.

**Decision.** A9 is one page, newest first: the response never carries
`cursor`, and any `cursor` query parameter is 400 `cursor`. A campaign
list is bounded by the budget rules (at most a handful of campaigns per
location), so paging is not needed; if it ever is, it comes back as an
optional `cursor` the way C1 and K1 have it.

**Files.** `docs/build/CONTRACTS.md` 6.A (A9), `docs/adr/ADR-A-meta-ads.md`
test row 9, `application/docs/openapi/meta-ads.yaml`.
