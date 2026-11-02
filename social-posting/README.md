# social-posting

Social posting: scheduled Facebook and Instagram posts from the menu (feature socialPosting).

- Decision record: `docs/adr/ADR-G-social-posting.md`; contract: `docs/build/CONTRACTS.md`
  (feature G, sections 0, 4, 5, 6.G, 9 and 12).
- Built in Run 2. No resources until Run 2: Run 0 instantiates the
  module (`social-posting.tf`) with only `environment` and the empty `wiring` output.
- Routes: `network/api-gateway/social-posting-routes.tf` (`local.social_posting_routes`).
- ECR repositories already exist (`module "social_posting_ecr"` in `config.tf`).
