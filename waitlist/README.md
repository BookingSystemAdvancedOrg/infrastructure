# waitlist

Waitlist: a walk-in and online queue that offers freed tables (feature waitlist).

- Decision record: `docs/adr/ADR-F-waitlist.md`; contract: `docs/build/CONTRACTS.md`
  (feature F, sections 0, 4, 5, 6.F, 9 and 12).
- Built in Run 2. No resources until Run 2: Run 0 instantiates the
  module (`waitlist.tf`) with only `environment` and the empty `wiring` output.
- Routes: `network/api-gateway/waitlist-routes.tf` (`local.waitlist_routes`).
- ECR repositories already exist (`module "waitlist_ecr"` in `config.tf`).
