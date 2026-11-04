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

## 2026-11-03: site-kit's builder pages keep the nav Bar as markup (Run 1 exception)

**Contradiction.** RULES.md (Brand) says every bar-like element uses the
Bar family from `packages/brand` and is never hand-rolled. The site
builder's `SitePage` (and the draft preview around it) render the page nav
as the Bar's markup (`bq-bar bq-bar--nav`, `bq-bar__items`,
`bq-bar__item`) instead of `<Bar variant="nav">`, because `SitePage` is
also rendered on the server by the render Lambda (react-dom/server), whose
bundle does not include `@booqy/brand` (site-kit does not depend on it).

**Decision.** Accepted for Run 1 as a documented exception, limited to
`packages/site-kit/src/features/site-builder/SitePage.tsx`: the markup
must stay class-for-class identical to the brand nav Bar and uses brand
tokens only (brand-lint still applies). The draft preview shows only this
one bar (the separate preview page bar is removed), and in the preview its
items open the draft page inside the preview instead of the live
`/<slug>`.

**Follow-up (Run 2, brand guardian).** Export a static, SSR-safe nav Bar
from `packages/brand` (plain markup component or render helper with no
browser-only imports) and switch `SitePage` to it, then delete this
exception.

**Files.** `customer-front-end/packages/site-kit/src/features/site-builder/{SitePage,PreviewPage}.tsx`,
`site-builder.css`, `SitePage.test.tsx`.

## 2026-11-03: campaign `error.code` gains `start_failed`

**Defect.** The 15-minute sweep in `application/functions/meta-ads-jobs/app.py`
(`restart_stranded`) marks a campaign `failed` with
`error: {code: start_failed}` when a publish that sat in `publishing`
without an `executionArn` for 10 minutes cannot be started. CONTRACTS.md
6.A and ADR-A only knew the MarkFailed codes (`meta_unavailable` and the
guard codes), and the OpenAPI fragment's `error.code` was an untyped
string, so the admin had no contract for the new value.

**Decision.** A campaign's `error{code}` (A9/A10, status `failed`, never
a `field`) is a MarkFailed code or `start_failed`. Admin renders
`start_failed` as "Annonsen kom aldrig i gång. Skapa den igen." (the
owner creates a new campaign; no Meta objects exist, so there is nothing
to retry). The code is `start_failed` and not a new value because B5
already uses it for the same situation (site-builder publish whose
StartExecution failed) and the admin maps codes to text per feature.

**Files.** `docs/build/CONTRACTS.md` 6.A (A8 idempotency, A10),
`docs/adr/ADR-A-meta-ads.md` data model, errors and test plan,
`application/docs/openapi/meta-ads.yaml` (`MetaAdsCampaign.error`).
Follow-up for admin: `admin-front-end/src/features/meta-ads/api.ts`
`FAILED_LABEL` needs the `start_failed` entry.

## 2026-11-03: the 15-minute sweep also restarts stranded publishes

**Contradiction.** ADR-A decision 6 and its Terraform section described
the `meta-ads-jobs` schedule as a kill-switch sweep only, and the IAM
call-out gave `states:StartExecution` to the API role alone. Since fix
round 2 (`application` `restart_stranded`, `infrastructure/meta-ads/main.tf`
`RestartStrandedPublish`) the same sweep starts publishes whose
StartExecution was lost, and the jobs role holds `states:StartExecution`
on the publish state machine.

**Decision.** The sweep is one schedule with two duties per connected
tenant: pause active campaigns of blocked tenants (kill switch) and start
every campaign still `publishing` without an `executionArn` that is at
least 10 minutes old, using the campaign id as the execution name so a
start the API already made is a no-op (`ExecutionAlreadyExists`); a start
that fails marks the row `failed` with `start_failed` (entry above). The
`meta-ads-jobs` role gets `states:StartExecution` on `<prefix>meta-ads-publish`
only (IAM call-out in ADR-A; already in `meta-ads/main.tf` and README).
The 10-minute wait keeps the sweep behind the owner's own retry of A8,
which starts the row immediately.

**Files.** `docs/adr/ADR-A-meta-ads.md` decision 7, Terraform modules
and IAM, test plan; `docs/build/CONTRACTS.md` 6.A (A8 idempotency).

## 2026-11-04: phone agent counter-offers (ADR-L decision 13)

**Contradiction.** The owner's instruction of 2026-11-04 (PIPELINE.md)
asked for a counter-offer rule the ADR did not have: ADR-L only said
"agent offers at most three times; full day -> it asks about the next day
itself", `get_availability` took only `date`, `partySize` and a time
range, and nothing said how a nearby table is offered when the location
has a floor plan.

**Decision.** The order is fixed in ADR-L decision 13 and the owner
trusts the recommendation: (1) requested time free -> book it; (2) time
taken -> the three closest free times the same day on both sides of the
requested time (distance first, tie to the earlier time, spoken in clock
order); (3) whole day full -> the next day once, then a callback, never a
third day; (4) a nearby table at the requested time when the location has
a published floor plan, offered before the time shift: two free tables on
the same floor at most 1.0 m apart whose seats fit (`adjacent_pair`), a
larger table the online rule keeps from this party (`larger`), or a table
marked phone-only (`phone_only`); per location `counterOffers{nearbyTables,
phoneOnlyTables}` (both default true). `hold_table` answers the
counter-offer in the same call that finds the time taken, so the happy
path stays one tool call. The call row and `PhoneCall.Ended` carry
`counterOffer` (new enum `CounterOffer`). Owner choices stay marked
**[NEEDS YOUR OK]** in the ADR: three offers and earlier-wins, one next
day then callback, the nearby-table interpretation and its 1.0 m gap,
nearby before times, the toggle defaults. Provider contracts, prices,
retention, legal wording and IAM are not touched by this decision.

**Reason.** The owner's rule is the natural phone conversation and keeps
the agent inside the existing availability engine (no new data, no new
tool): the guest view already returns the online options and why every
other table is not offered, the staff view returns every free table, and
the public active layout carries the geometry in metres. Offering the
nearby table first keeps the caller's time, which is what they asked for.

**Files.** `docs/adr/ADR-L-phone-agent.md` (decision 13, tool table, data
model, L4, events, IAM, test plan), `docs/build/CONTRACTS.md` (1.3, 5,
6.L L4/L7/L8 and the tool note, 13, 14, 17.1),
`application/contracts/booqy.yaml` and the five generated targets,
`application/shared/agent_model.py` (counter-offer sentences and flow in
the simulator), `application/tests/test_phone_agent_counter_offers.py`,
`application/tests/test_contracts.py`.

## 2026-11-04: the phone agent books through the staff route, with no server-side hold

**Contradiction.** ADR-L's tool table sent `hold_table` to the public
hold route `POST /locations/{l}/holds` and `create_reservation` to the
public online route. Both run Turnstile (when `TURNSTILE_REQUIRED`) and
the per-IP request guard, which the agent's synthesized event cannot
satisfy, the online route needs `acceptTerms` from the guest, and the hold
only accepts online table options, so the nearby-table counter-offer could
never be held there.

**Decision.** The agent books the way staff book a phone call today:
`POST /locations/{l}/reservations/manual` with `source: "phone"`,
`notifyGuest: true` and explicit `tableIds`, under the agent principal
(a staff user). `hold_table` is a bookability check with the shared
availability engine that returns a proposal id valid for the call; there
is no server-side hold (staff phone bookings have none today; the manual
route's conditional write refuses a table taken in the meantime and the
agent re-offers). Consequence: the manual route never asks a card
guarantee, so in v1 a party that would need one online gets a callback
instead of a booking. The upgrade (manual route accepts `guarantee: true`
for `source: phone`, creates the pending-guarantee reservation and
returns `guaranteeRequired`, which makes decision 8's SMS link work) is a
Run 2 hotspot change **[NEEDS YOUR OK]**.

**Reason.** It is the only path that needs no change to the public
routes' bot and attempt protection, that can seat a nearby table, and
that produces the existing `source: phone` reservations the Bokningar
page already shows. A hold-less phone booking is what the restaurant does
by hand today.

**Files.** `docs/adr/ADR-L-phone-agent.md` (decision 13 "Hold and
booking path", tool table rows `hold_table` and `create_reservation`),
`docs/build/CONTRACTS.md` 6.L tool note.

## 2026-11-04: feature A widens to all ad platforms behind a platform adapter port (ADR-A2)

**Contradiction.** The owner's instruction of 2026-11-04 asks for ad
campaigns on all platforms with spend set by the restaurant, recurring
campaigns, a first-time guide and a daily view; ADR-A, CONTRACTS.md 6.A
and the Run 1 code are Meta-only, with `MetaGraph` called straight from
the publish workflow and the insights job, and the routes, table keys,
events and entitlement all named `meta-ads`.

**Decision.** `docs/adr/ADR-A2-ad-platforms.md` (addendum to ADR-A): one
port `AdPlatform` (`shared/ad_platform.py`) behind the existing wizard,
`MetaAdPlatform` wrapping the Run 1 `MetaGraph` first (no behaviour
change for Meta), then Google Ads, then TikTok, others only when their
API lets a third party create ads on the restaurant's own account. Meta's
routes, table, events and entitlement stay as built; the platform-neutral
additions (connection list, spend confirmation, schedules, the daily
view) get their own contract rows at the Run 2 cut (CONTRACTS.md 6.A2,
Fable). Spend always stays inside the existing per-campaign bounds,
monthly cap, kill switch and alarm, and starts only after an explicit
confirmation showing the total. Money screens stay owner-only and
hidden-amount for staff unless the owner decides otherwise, which the ADR
flags as its first question. Work is split: A2 (port, Meta adapter,
confirmation, schedules, guide, daily view) in Run 2 next to G; A3 Google
Ads and A4 TikTok in Run 3 behind simulators, real adapters only after
the platform approvals the ADR lists. No separate run.

**Reason.** The wizard, caps, kill switch, UTM attribution and insights
are platform-neutral already; only the five Meta calls are not. A port
lets each platform ship as one adapter plus its connection guide without
touching the others, and the Meta code on `dev` keeps working while the
port is introduced. Google Ads and TikTok approvals take weeks and are
human actions, so their adapters cannot be verified in Run 2 anyway.

**Files.** `docs/adr/ADR-A2-ad-platforms.md` (new),
`docs/adr/ADR-A-meta-ads.md` (addendum pointer), `docs/build/STATUS.md`,
`docs/build/PIPELINE.md`.
