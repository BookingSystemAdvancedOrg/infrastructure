# gift-cards

Gift cards: sold on the restaurant site, redeemed online and in Kassa (feature giftCards).

- Decision record: `docs/adr/ADR-E-gift-cards.md`; contract: `docs/build/CONTRACTS.md`
  (feature E, sections 0, 4, 5, 6.E, 9 and 12).
- Built in Run 2. No resources until Run 2: Run 0 instantiates the
  module (`gift-cards.tf`) with only `environment` and the empty `wiring` output.
- Routes: `network/api-gateway/gift-cards-routes.tf` (`local.gift_cards_routes`).
- ECR repositories already exist (`module "gift_cards_ecr"` in `config.tf`).
