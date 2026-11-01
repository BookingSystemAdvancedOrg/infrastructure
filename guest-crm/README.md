# guest-crm

Guest CRM: guest profiles, visit history and segments built from bookings, orders and catering (feature guestCrm).

- Decision record: `docs/adr/ADR-C-guest-crm.md`; contract: `docs/build/CONTRACTS.md`
  (feature C, sections 0, 4, 5, 6.C, 9 and 12).
- Built in Run 1. No resources until Run 1: Run 0 instantiates the
  module (`guest-crm.tf`) with only `environment` and the empty `wiring` output.
- Routes: `network/api-gateway/guest-crm-routes.tf` (`local.guest_crm_routes`).
- ECR repositories already exist (`module "guest_crm_ecr"` in `config.tf`).
