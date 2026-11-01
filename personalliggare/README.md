# personalliggare

Personalliggare: the staff ledger (check-in and check-out) for Skatteverket (feature personalliggare).

- Decision record: `docs/adr/ADR-H-personalliggare.md`; contract: `docs/build/CONTRACTS.md`
  (feature H, sections 0, 4, 5, 6.H, 9 and 12).
- Built in Run 2. No resources until Run 2: Run 0 instantiates the
  module (`personalliggare.tf`) with only `environment` and the empty `wiring` output.
- Routes: `network/api-gateway/personalliggare-routes.tf` (`local.personalliggare_routes`).
- ECR repositories already exist (`module "personalliggare_ecr"` in `config.tf`).
