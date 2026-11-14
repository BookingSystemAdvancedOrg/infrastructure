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

## 2026-11-04: gift-cards table has `TXREF#<txId>`, `JOB`/`NIGHTLY` and three `byExpiry` buckets

**Contradiction.** CONTRACTS.md 4 listed the `<prefix>gift-cards` rows as
`SETTINGS`, `PURCHASE#`, `CARD#`, `CODE#` and `CARD#<c>#TX#<tx>`, with
`byExpiry` holding only `EXPIRY#<day>`. The code
(`shared/features/gift_cards/__init__.py`, `functions/gift-cards/app.py`,
`infrastructure/gift-cards/main.tf`) also writes `TXREF#<txId>`
(`cardId`, `verifiedAt?`, same transaction as the TX row, so Kassa can
verify a redemption by its `paymentId`), a tenant-less `JOB`/`NIGHTLY`
row (`lastDay`, the nightly job's resume point) and two more `GSI2PK`
buckets: `CLEANUP#<day>` on a used/expired/void card (last TX + 24
months, the contact clean-up of ADR-E "Retention") and
`UNVERIFIED#<day>` on the TXREF of a Kassa redeem Kassa has not verified
(reversed after 30 minutes; the key is removed on verify, reverse and
purge).

**Decision.** The table row in CONTRACTS.md 4 names all of them. One
sparse index carries the three nightly day-buckets rather than three
indexes: each row sits in exactly one bucket at a time, the job walks the
same `GSI2PK = <bucket>#<day>` query for every bucket, and a card leaves
the expiry bucket for the clean-up bucket in the same conditional update
that changes its status. `TXREF` exists because the Kassa hook carries
only `paymentId`, not `cardId`, and the TX key is `CARD#<c>#TX#<tx>`.

**Files.** `docs/build/CONTRACTS.md` section 4.

## 2026-11-04: notification kind `google-business.review-request`

**Contradiction.** CONTRACTS.md 9.4 said D's review requests use the
marketing mail path and listed no `google-business.*` kind, while
`functions/google-business-jobs/app.py` `_deliver` sends the SMS variant
by invoking `notification:live` with `kind: google-business.review-request`
(`channel: sms`, `replyTo: null`) and the email variant through
`shared/marketing_mail.send(kind="google-business.review-request")`.

**Decision.** `google-business.review-request` is a contract kind in 9.4
(SMS through notification; the email keeps the marketing mail path and
uses the same kind string so billing sees one kind). Section 14 adds
google-business-jobs to the callers of `notification:live`.

**Reason.** Review SMS must get the tenant sender, number prefixes, part
counting and per-kind billing that only notification applies; the email
needs List-Unsubscribe and the signed withdraw link that only marketing
mail applies. One kind string keeps the usage report per feature.

**Files.** `docs/build/CONTRACTS.md` 9.4 and 14.

## 2026-11-04: review-request SMS is sent via `notification:live`, not SNS

**Contradiction.** ADR-D decision 7 said "SNS for SMS" and the IAM
call-out gave the jobs role `sns:Publish`. The built sender never
publishes to SNS: it invokes the notification alias (entry above), which
is also what 9.4 requires of every feature.

**Decision.** ADR-D 7 and its IAM call-out read "SMS via
`notification:live` (Lambda invoke, kind `google-business.review-request`)",
and the jobs role needs `lambda:InvokeFunction` on `notification:live`
and no `sns:Publish`. The module (`infrastructure/google-business/main.tf`,
fix round of 2026-11-04) sets `NOTIFICATION_FUNCTION_NAME` from the new
variable `notification_function_arn` (root `google-business.tf` passes
`module.notification_fn.alias_arn`) and replaces the `SendReviewSms`
`sns:Publish` statement with `InvokeNotification` on that alias.

**Reason.** A second SMS sender would duplicate the prefix, part-count
and billing rules and leave review SMS out of the usage report; the
notification Lambda already has the SNS permission and the dev outbox.

**Files.** `docs/adr/ADR-D-google-business-profile.md` decision 7, IAM,
external dependencies.

## 2026-11-04: E10 "Skicka ny kod" rotates the code and is confirmed in the UI

**Contradiction.** ADR-E decision 3 said "owners can resend" and route 10
returned a bare 202, as if the stored code could be mailed again. Codes
are never stored (HMAC + last4 only), so a resend is impossible; the built
E10 (`functions/gift-cards/app.py` `resend`) generates a new code, writes
the new `CODE#` row, deletes the old one and replaces `codeHmac`/`last4`
on the card in one transaction, then mails the new code as
`gift-cards.code-resend` and answers 202 `{last4}`. The admin
(`PresentkortPage.tsx`) asks the owner to confirm "Skicka ny kod" because
the old code stops working, and shows the new last4.

**Decision.** E10 is documented as rotation: 202 `{last4}`, 409
`card_expired`/`card_void` (active cards only), 409 `changed_retry` on a
concurrent change; never idempotent, only the latest code works; the UI
confirms first. ADR-E 3, route 10 and test row 10 say the same.

**Reason.** Keeping codes retrievable would turn a leaked admin session
into spendable money (ADR-E alternatives); rotation gives the owner a
working "send again" without storing anything, and the confirmation step
stops an owner from voiding a code a guest is about to use.

**Files.** `docs/build/CONTRACTS.md` 6.E (E10) and 9.4,
`docs/adr/ADR-E-gift-cards.md` decision 3, route 10, test row 10.

## 2026-11-04: `charge.refunded` voids only on a full refund; partial refunds are flagged (code follow-up)

**Contradiction.** ADR-E decision 9 said a refunded purchase "voids the
card (remaining balance only; a partly used card shows a warning)".
Review finding 10 asks that a partial Stripe refund (`amount_refunded <
amount`) must not void a card the guest still holds. The built handler
(`functions/gift-cards/app.py` `stripe_event`) voids the remaining balance
on every `charge.refunded` and on a lost `charge.dispute.closed`
(`void-<chargeId>` TX, idempotent), reads no `amount_refunded` and writes
no warning or flag.

**Decision.** The contract is: full refund or lost dispute -> void;
partial refund -> no balance change, the card is flagged for the owner
(who settles it with E8/E9); a won dispute is ignored. ADR-E 9 states
this and says plainly that the branch voids on every `charge.refunded`
today, so nobody reads the ADR as describing shipped behaviour.
Code follow-up for the gift-cards worker: compare `amount_refunded` with
`amount`, flag the card on a partial refund and add the test
(finding 10). The flag's shape (card attribute and E6/E7 field) is set
by that worker and recorded here when built.

**Reason.** Stripe sends `charge.refunded` for partial refunds too (an
owner refunding a shipping-style adjustment, or Stripe's own partial
reversal). Voiding then takes money from a guest who was not refunded;
the liability stays on 2421 until the owner acts.

**Files.** `docs/adr/ADR-E-gift-cards.md` decision 9.

## 2026-11-04: social-posting schedule creation treats `ConflictException` as success

**Contradiction.** ADR-G idempotency said `create_schedule` on an existing
name is "treated as success after comparing the time". The built route 6
(`functions/social-posting/app.py` `schedule`, `_create_schedule`) deletes
the post's schedule, creates it for the new time and swallows a
`ConflictException` without reading the existing schedule's time.

**Decision.** Conflict is success, no time comparison. The schedule name
is the post id and the worker re-reads the post's status and
`scheduledAt` at fire time, so a schedule left over from a race can only
fire a no-op (`noop` when the post is no longer `scheduled`), and the
same-time retry already returns the current post before any Scheduler
call. The ADR text is corrected.

**Reason.** `GetSchedule` + compare + `UpdateSchedule` adds two calls and
a second race for no safety the fire-time check does not already give.

**Files.** `docs/adr/ADR-G-social-posting.md` idempotency paragraph.

## 2026-11-04: `needs_check` recovery should use `created_time` after the first attempt, not a caption match (code follow-up)

**Contradiction.** ADR-G decision 6 said the worker looks for "the
caption's marker hash" in the Page's latest posts. The built worker
(`_publish_channel`) appends no marker and adopts the first of the 25
most recent Page posts whose `message` equals the post's caption. Review
finding 10 asks for recovery by `created_time`: a Page post created after
the first attempt's timestamp for this post, so two posts with the same
caption on one Page (a weekly special) cannot be confused and a caption
Meta rewrote (trimmed whitespace, link preview) still matches.

**Decision.** The contract is recovery by `created_time` after the first
attempt (the attempt time is recorded on the channel state before the
Graph call); the caption is a secondary check, not the key. ADR-G 6
states this and says the branch still matches on caption only. Code
follow-up for the social-posting worker: store the attempt time on the
channel before `publish_page_photo`, have `recent_page_posts` return
`created_time`, and match on it (test: two posts with one caption, only
the later one is adopted).

**Reason.** Caption equality is neither unique nor stable on Meta's
side; the first attempt's time is known to Booqy and monotonic.

**Files.** `docs/adr/ADR-G-social-posting.md` decision 6.

## 2026-11-04: E9 refund writes the refund TX first, then refunds exactly that amount in Stripe

**Contradiction.** ADR-E route 9 and CONTRACTS.md 6.E described E9 as
"Stripe refund of the unused part, then the card", which is what the
first build did (`refund`: Stripe first, `change_balance` after). Fix
round 2 showed the race: a redemption between the balance read and the
card write makes Stripe refund more than the card still held, and a crash
after the Stripe call leaves a refunded card that can still be redeemed.

**Decision.** Built in application 55f372e: `refund` writes the card
first, one `refund` TX of the balance it read, conditional on the card
`version` (`change_balance(expect_version=...)`); a redemption in between
is 409 `changed_retry` with no Stripe call. Then Stripe refunds exactly
the TX amount (key `giftcard-refund-<txId>`) and `stripeRefundId` is set
on the TX. A Stripe failure is 502 `stripe_unavailable` with the card
already void; a retry with the same `txId` returns the card and finishes
the Stripe refund while `stripeRefundId` is missing, so there is one TX
and one Stripe refund however often the route is called. CONTRACTS.md
6.E, ADR-E 9, data model, route 9, idempotency and test row 9 say so.

**Reason.** Voiding first means the card can never be spent after money
has gone back; the Stripe call is idempotent by `txId`, so finishing it
later is safe, while a refund that outruns a redemption is not.

**Files.** `docs/build/CONTRACTS.md` 4 and 6.E,
`docs/adr/ADR-E-gift-cards.md` decision 9, data model, route 9,
idempotency, test row 9.

## 2026-11-04: `charge.refunded` partial flag and the code-email resend are built; new stored fields

**Contradiction.** The "code follow-up" entry above left the partial
refund flag unbuilt and its shape to the worker; the same review found
that a crash between the card write and the code email left an issued
card whose guest never got a code (the webhook replay answered
`already_issued`).

**Decision.** Built in application 55f372e, so ADR-E 9 no longer says
"as built the handler voids on every `charge.refunded`":
- `charge.refunded` voids only when `amount_refunded == amount`
  (`voided` / `already_void`); otherwise the balance is untouched and the
  card gets `partialRefundOre` (öre refunded in Stripe) and
  `partialRefundAt`, result `flagged:partial_refund`, plus a warning log
  line; the owner settles with E8 or E9.
- `codeSentAt` is stamped on the card once notification has accepted the
  code email (invoke status 202; anything else raises). A
  `payment_intent.succeeded` replay for an issued, active card without
  `codeSentAt` that is older than 2 minutes (`CODE_SEND_GRACE_SECONDS`;
  the first attempt may still be sending) rotates the code (E10's
  transaction) and sends `gift-cards.code` again, result `code_resent`; a
  concurrent change or a card no longer active answers `already_issued`.
- `stripeRefundId` on a `refund` TX (entry above).
The `stripe.event` result list in CONTRACTS.md 9.2 now names
`code_resent` and `flagged:partial_refund`; section 4 and the ADR-E data
model carry the fields. They are stored only: `card_detail` (E6/E7) and
the admin page do not show them yet.

**Reason.** A guest with a partly refunded purchase still holds a card;
voiding would take the money twice. Stripe replays
`payment_intent.succeeded` for a day, so the stamp lets the replay heal
a lost email without ever storing the code, and the grace keeps a slow
first send from producing two codes.

**Files.** `docs/build/CONTRACTS.md` 4, 9.2, 9.4;
`docs/adr/ADR-E-gift-cards.md` decisions 3 and 9, data model.

## 2026-11-04: `needs_check` recovery by `created_time` is built; A's Meta port must return it

**Contradiction.** The entry above left the `created_time` match as a
code follow-up for the social-posting worker.

**Decision.** Built in application 55f372e: the channel's first publish
lease stores `firstAttemptAt` (kept on later attempts), and FB
`needs_check` recovery adopts a Page post only when `message == caption`
and `created_time >= firstAttemptAt - 120 s` (`CLOCK_SKEW_SECONDS`,
Meta's clock against ours). A post without a parseable, timezone-aware
`created_time` never matches; with no match the worker publishes again,
as before (the first attempt's outcome was unknown). Tests: a post
created after the first attempt is adopted; last week's post with the
same caption, or one without `created_time`, is not. The Meta port has to
supply `created_time`: the simulator's `publish_page_photo`
(`shared/meta_graph.py`) stamps none and `shared/meta_graph_real.py` is
still the Run 0 skeleton, so `RealMetaGraph.recent_page_posts` must
request `fields=id,message,permalink_url,created_time` and return it,
and the simulator should stamp it at publish. That is feature A's port,
not G's files: Run 2 batch 1 open item 10 in STATUS.md.

**Reason.** The first attempt's time is known to Booqy and monotonic; a
caption is neither unique nor stable. Treating a missing `created_time`
as "not proven" errs toward a second post rather than adopting a
stranger's post, and the real port will return the field.

**Files.** `docs/build/CONTRACTS.md` 4; `docs/adr/ADR-G-social-posting.md`
decision 6, data model, external dependencies, test plan;
`docs/build/STATUS.md` Run 2 batch 1 open item 10.

## 2026-11-04: review SMS via `notification:live` confirmed in code; a refused send is retried by the schedule

**Contradiction.** The entry above recorded the decision from the
infrastructure fix; the application side had not been checked against
it, and a refused invoke counted as sent.

**Decision.** Confirmed on application 55f372e: `google-business-jobs`
`send_review` invokes `os.environ["NOTIFICATION_FUNCTION_NAME"]`
(`InvocationType=Event`, kind `google-business.review-request`,
`replyTo: null`) and never SNS; `infrastructure/google-business/main.tf`
sets the variable from `notification_function_arn`. New in the same
commit: an invoke status other than 202, or a failed email send, releases
the `REVJOB` claim (`sent` back to `scheduled`, `channel` and `sentAt`
removed) and deletes the cooldown row this attempt wrote, then raises, so
the Scheduler retry (and in the end the DLQ) sends it;
`ReviewRequest.Sent` is published only after the send. ADR-D 7 and
CONTRACTS.md 9.4 note it.

**Reason.** 9.4 has the caller record "sent" before invoking so Lambda
never sends twice; without the undo a refused invoke would have counted
as sent and the guest would never get the request.

**Files.** `docs/adr/ADR-D-google-business-profile.md` decision 7,
`docs/build/CONTRACTS.md` 9.4.

## 2026-11-04: `@booqy/site-kit` depends on `@booqy/brand`

**Contradiction.** ADR-BRAND-sharing links the customer-front-end
workspace (guest site and site-kit) to `packages/brand`, but
`@booqy/site-kit` as a published package had no runtime dependency on
the brand package; its F and E pages reached for brand components.

**Decision.** From customer-front-end 2f43d25 (2026-11-04) the Kö and
Presentkort pages in site-kit use `@booqy/brand` (banner, tab Bar,
Button), so `packages/site-kit/package.json` declares
`"@booqy/brand": "0.1.0"` in `dependencies`. The workspace builds and
tests brand before site-kit (`npm run build -w @booqy/brand && npm run
build -w @booqy/site-kit`; same order for `test`), and a site-kit release
needs a published brand version of the same or a compatible number. The
dependency direction is brand -> site-kit -> apps, never the reverse.

**Reason.** One copy of the brand components for the restaurant site's
feature pages instead of a second one inside site-kit; the brand package
already ships from the same workspace.

**Files.** `docs/adr/DECISIONS.md` only (the dependency itself lives in
customer-front-end `packages/site-kit/package.json`).

## 2026-11-04: site-kit's `@booqy/brand` dependency must become the npm alias before the first site-kit release; the brand CSS is loaded by site-kit or by the consuming site

**Contradiction.** The entry above has `packages/site-kit/package.json`
declare `"@booqy/brand": "0.1.0"`. Inside the customer-front-end
workspace that resolves to `packages/brand`, but ADR-BRAND-sharing
point 3 says the package is published to GitHub Packages as
`@bookingsystemadvancedorg/brand` and that consumers use the npm alias
`"@booqy/brand": "npm:@bookingsystemadvancedorg/brand@^0.1.0"`. A
published `@booqy/site-kit` with the bare `0.1.0` specifier would ask
the registry for a package that does not exist under that name. The
brand components site-kit now renders (Bar, Button) also need the brand
stylesheet, and nothing in site-kit loads it.

**Decision.** Not a break today: `@booqy/site-kit` is unpublished and the
workspace resolves brand from source (`@booqy/source` condition in
site-kit's `tsconfig.json` and `vite.config.ts`, customer-front-end
2f43d25). Before the first site-kit release, and only once the brand
package has been published, `packages/site-kit/package.json` must
declare the dependency as
`"@booqy/brand": "npm:@bookingsystemadvancedorg/brand@^0.1.0"` (the
alias of ADR-BRAND-sharing point 3), so a consumer installing site-kit
pulls brand from GitHub Packages under the same import name. The brand
CSS is loaded exactly once by one of two parties: either site-kit's
`styles` entry (`src/styles.ts`) imports `@booqy/brand/styles.css`, or
the consuming site does (the guest site does today in `src/main.tsx`);
the site-kit README states which, and the release checklist checks both
the alias and the CSS. The brand package stays `external` in site-kit's
library build either way (never bundled twice).

**Reason.** The bare version specifier is correct for the workspace and
wrong for the registry; the alias keeps the import name `@booqy/brand`
in every repo (ADR-BRAND-sharing point 1) while installing the published
name. Deferring the switch is safe because site-kit cannot be installed
from a registry yet, and switching before brand is published would
break the workspace install.

**Files.** `docs/adr/DECISIONS.md` only; the change lands in
customer-front-end `packages/site-kit/package.json` (and `src/styles.ts`
or the README) with the first site-kit release.

## 2026-11-04: waitlist settings are rolled back when the location mirror is denied; the mirror uses `ReturnValues` NONE

**Contradiction.** F6 (`PUT /locations/{locationId}/waitlist/settings`)
writes the settings row first, then mirrors `publicJoin` onto the
location row for `/site-config`. The IAM statement `MirrorPublicJoin`
(infrastructure c1d574e) now allows the `UpdateItem` only with
`dynamodb:Attributes` limited to `PK`, `SK`, `waitlist` and
`dynamodb:ReturnValues` equal to `NONE`, so a mirror call that asks for
return values is denied (and one against a missing location row fails
its condition) after the settings row has already been saved: settings
and mirror would disagree and `/site-config` would show the old
`publicJoin`.

**Decision.** Built in application 3660cd5. The mirror `UpdateItem` keeps
`ReturnValues` at its default `NONE` (the policy allows nothing else).
When the mirror raises a `ClientError`, `_undo_settings` puts the
settings row back before the error propagates: the previous item is
written again, or the row is deleted when there was none (previous
`version` 0), both conditional on `version = <the version this request
wrote>` so a later save by the owner is never overwritten; a failed
condition is swallowed (someone saved after us, their save stands). The
request then fails as before and the owner saves again on the old
version. The IAM condition stays as it is: the role must not read other
location attributes back through `ReturnValues`.

**Reason.** The two writes are not in one transaction (different tables,
and the location table is the hotspot's); restoring the first write on a
denied second one is the cheapest way to keep the owner's settings and
the public site consistent. Requiring `NONE` is the same rule
site-builder's mirror already follows.

**Files.** `docs/adr/DECISIONS.md` (this entry records the rollback;
`docs/adr/ADR-F-waitlist.md` route 6 and `docs/build/CONTRACTS.md` 6.F F6
describe the mirror itself); `waitlist/main.tf` `MirrorPublicJoin`
(infrastructure c1d574e); `functions/waitlist/app.py` `put_settings` /
`_undo_settings` and `tests/test_waitlist.py` (application 3660cd5).

## 2026-11-04: phone agent counter-offers (ADR-L decision 13)

**Contradiction.** The owner's instruction of 2026-11-04 (PIPELINE.md)
asked for a counter-offer rule the ADR did not have: ADR-L only said
"agent offers at most three times; full day -> it asks about the next day
itself", `get_availability` took only `date`, `partySize` and a time
range, and nothing said how a nearby table is offered when the location
has a floor plan.

**Decision.** The order is fixed in ADR-L decision 13 and the owner
trusts the recommendation: (1) requested time free -> book it; (2) a
nearby table at the requested time when the location has a published floor
plan, offered before the time shift: two free tables on the same floor at
most 1.0 m apart whose seats fit (`adjacent_pair`), a larger table the
online rule keeps from this party (`larger`), or a table marked phone-only
(`phone_only`); per location `counterOffers{nearbyTables, phoneOnlyTables}`
(both default true); (3) time taken -> the three closest free times the
same day on both sides of the requested time (distance first, tie to the
earlier time, spoken in clock order); (4) whole day full -> the next day
once per day the caller asks for, then a callback, never a third day.
`hold_table` answers the
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

## 2026-11-05: `phone-agent-call` reserved concurrency is 2 in dev only; prod is undecided

**Defect.** `phone-agent-call` answers the provider webhooks and the agent
turn endpoint on a public Function URL with no API Gateway throttle and no
reserved concurrency (Run 2 batch 2 review follow-up). The key and
signatures refuse a forged request, but a flood still runs, and bills, the
function.

**Decision.** New root variable `phone_agent_call_reserved_concurrency`
(number, default -1 = unreserved, validated as -1 or a whole number >= 0),
passed to the `phone-agent` module as `call_reserved_concurrency` and set
on `phone-agent-call` only. `dev.tfvars` sets 2; `prod.tfvars` does not set
it, so prod stays unreserved. The prod value is an open owner decision
(PIPELINE.md "Needs owner") to be made before L goes live.

**Reason.** Dev only ever sees test calls, so 2 caps what a flood can cost
there without getting in the way of testing. In prod one live call holds
an execution per turn, so 2 would turn away real callers at the second
simultaneous restaurant call; the right number depends on the plan matrix
and expected call volume, which the owner has not decided. Adds no IAM and
changes no existing resource (the three phone-agent Lambdas are new in
this PR). AWS refuses a reservation that leaves fewer than 10 unreserved
in the account, so the dev account's concurrency quota must be at least 12
(unverified: no AWS access in the run).

**Files.** `phone-agent.tf`, `phone-agent/main.tf`,
`phone-agent/variables.tf`, `phone-agent/tests/concurrency.tftest.hcl`,
`phone-agent/README.md`, `dev.tfvars`, `docs/build/PIPELINE.md`.

## 2026-11-05: dev reserved concurrency for phone-agent-call set to -1 (unreserved) until the quota is raised
The dev apply of infrastructure#43 failed: AWS refused reserved concurrency 2 because the dev account would drop below the minimum 10 unreserved executions (quota below 12). Dev was left partly applied. To unblock all dev deploys, dev.tfvars now sets phone_agent_call_reserved_concurrency = -1. This departs from the owner's cap of 2 and is temporary: raise the dev Lambda concurrency quota (owner, AWS Service Quotas) to at least 12, then set it back to 2. Feature is off for every tenant; the exposure is the public Function URL (simulator webhooks, see review finding F3).

## 2026-11-05 K-finish decisions (run-20261105T1510Z)
- K ticket-type edits after sales: price and VAT may change; existing orders, tickets and TX rows keep theirs. A VAT change is flagged needs_accountant_review with an append-only trail, not blocked. The flag stays until a later accountant-review clear flow exists (needs owner/accountant decision). Reviewed by Fable (application#77).
- Ticket type "description" = existing `includes` field (label "Beskrivning").
- Cap guard on every type counter write (add/remove of a cap during checkout, refund, expiry or late issue cannot break seatsLeft = cap - taken).
- Edits frozen once a published event can no longer sell (409 invalid_state).
- Customer pages (customer#19): when `events` is off keep the existing redirect to the start page (no 404 page); gift transfer built, resale and Wallet hidden until backend has them; no QR on the thank-you page (tickets issued by webhook, link by email only); held seats expire by the 15-minute TTL, no release route (accepted).
- Ownership: root package.json/lock (Playwright devDependency), playwright.config.ts, e2e/**, docs/screenshots/** in customer-front-end accepted as orchestrator-shared paths; re-frozen after customer#19.
- Open note: ticket tokens travel in the API path (/public/tickets/{token}), so API Gateway access logs may contain them; consider a header in a later contract change.
