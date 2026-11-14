# events-tickets

Events and tickets: ticketed events with occurrences, prepaid checkout on the restaurant's Stripe account, QR tickets, door check-in, transfers and refunds (feature events).

- Decision record: `docs/adr/ADR-K-events-tickets.md`; contract: `docs/build/CONTRACTS.md`
  (feature K, sections 0, 4, 5, 6.K, 9 and 12).
- Built in Run 2 batch 3: table `<prefix>events-tickets` (GSIs `byOccurrence`,
  `byLocationDay`), Lambda `events-tickets` with its own role, the pepper secret
  `<prefix>events-tickets/code-pepper` (random), Scheduler group `<prefix>events-tickets`
  (sweep every 5 minutes, nightly 02:45 Europe/Stockholm), Errors alarm.
- Not in this run (no resources, no IAM): Wallet pass secrets, table pick, event images.
- Routes: `network/api-gateway/events-tickets-routes.tf` (`local.events_tickets_routes`).
- ECR repositories already exist (`module "events_tickets_ecr"` in `config.tf`).
