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
