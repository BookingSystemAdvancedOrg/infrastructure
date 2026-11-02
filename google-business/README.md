# google-business

Google Business Profile: opening hours sync and review requests (feature googleBusiness).

- Decision record: `docs/adr/ADR-D-google-business-profile.md`; contract: `docs/build/CONTRACTS.md`
  (feature D, sections 0, 4, 5, 6.D, 9 and 12).
- Built in Run 2. No resources until Run 2: Run 0 instantiates the
  module (`google-business.tf`) with only `environment` and the empty `wiring` output.
- Routes: `network/api-gateway/google-business-routes.tf` (`local.google_business_routes`).
- ECR repositories already exist (`module "google_business_ecr"` in `config.tf`).
