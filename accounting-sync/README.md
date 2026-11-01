# accounting-sync

Fortnox and Visma: automatic daily vouchers posted to the restaurant's bookkeeping (feature accountingSync).

- Decision record: `docs/adr/ADR-I-fortnox-visma.md`; contract: `docs/build/CONTRACTS.md`
  (feature I, sections 0, 4, 5, 6.I, 9 and 12).
- Built in Run 3. No resources until Run 3: Run 0 instantiates the
  module (`accounting-sync.tf`) with only `environment` and the empty `wiring` output.
- Routes: `network/api-gateway/accounting-sync-routes.tf` (`local.accounting_sync_routes`).
- ECR repositories already exist (`module "accounting_sync_ecr"` in `config.tf`).
