# meta-ads

Meta ads: owners connect their Meta business assets and run ad campaigns for bookings, orders and catering (feature metaAds).

- Decision record: `docs/adr/ADR-A-meta-ads.md`; contract: `docs/build/CONTRACTS.md`
  (feature A, sections 0, 4, 5, 6.A, 9 and 12).
- Built in Run 1. No resources until Run 1: Run 0 instantiates the
  module (`meta-ads.tf`) with only `environment` and the empty `wiring` output.
- Routes: `network/api-gateway/meta-ads-routes.tf` (`local.meta_ads_routes`).
- ECR repositories already exist (`module "meta_ads_ecr"` in `config.tf`).
