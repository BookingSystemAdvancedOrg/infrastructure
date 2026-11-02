# events-tickets

Events and tickets: ticketed events with occurrences, prepaid checkout on the restaurant's Stripe account, QR tickets, door check-in, transfers and refunds (feature events).

- Decision record: `docs/adr/ADR-K-events-tickets.md`; contract: `docs/build/CONTRACTS.md`
  (feature K, sections 0, 4, 5, 6.K, 9 and 12).
- Built in Run 2. No resources until Run 2: the Run 0 addendum instantiates the
  module (`events-tickets.tf`) with only `environment` and the empty `wiring` output.
- Routes: `network/api-gateway/events-tickets-routes.tf` (`local.events_tickets_routes`).
- ECR repositories already exist (`module "events_tickets_ecr"` in `config.tf`).
