# guest-crm

Guest CRM (feature C, `guestCrm`): one profile per guest per restaurant,
keyed by hashed contact identifiers, segments and consent-checked exports to
marketing campaigns.

- Decision record: `docs/adr/ADR-C-guest-crm.md`; contract: `docs/build/CONTRACTS.md`
  (feature C, sections 0, 4, 5, 6.C, 9 and 12).
- Resources: table `<prefix>guest-crm` (+ sparse GSI `byLastSeen`), Lambdas
  `guest-crm` (API, hooks, rebuild job) and `guest-crm-sync` (streams), the
  three stream mappings (filters that mirror `classify()`: reservation status; order paid or completed; catering confirmed/delivered/closed or paid; `ReportBatchItemFailures`, SQS DLQ
  `<prefix>guest-crm-sync-dlq`), roles, log groups, Errors, DLQ and IteratorAge alarms (guest-crm-sync is the last direct stream reader: `docs/adr/DECISIONS.md` 2026-11-03).
- Routes: `network/api-gateway/guest-crm-routes.tf` (`local.guest_crm_routes`).
- IAM (new roles only): own table + GSI; GetItem/Query on the reservation,
  order and catering-requests tables; stream read on their streams; Query on
  the consent log; GetItem on the marketing table; `events:PutEvents` on the
  bus with `events:source = booqy.guest-crm`; invoke itself (rebuild). The
  hook callers' invoke grants (guest-privacy, marketing, marketing-send,
  tenant-purge) already exist from Run 0.
- Stream readers: reservation and catering-requests get a third reader, the
  order stream a fourth (notification, marketing-sync, print-jobs). DynamoDB
  recommends at most two per shard; more readers delay (throttle) reads,
  they do not lose records. Watch `ReadThrottleEvents`/IteratorAge.
