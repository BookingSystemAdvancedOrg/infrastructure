# site-builder

Site builder: owners edit, preview and publish their restaurant website (feature siteBuilder; AI edits in B2, Run 2).

- Decision record: `docs/adr/ADR-B-site-builder.md`; contract: `docs/build/CONTRACTS.md`
  (feature B, sections 0, 4, 5, 6.B, 9 and 12).
- Built in Run 1. No resources until Run 1: Run 0 instantiates the
  module (`site-builder.tf`) with only `environment` and the empty `wiring` output.
- Routes: `network/api-gateway/site-builder-routes.tf` (`local.site_builder_routes`).
- ECR repositories already exist (`module "site_builder_ecr"` in `config.tf`).
