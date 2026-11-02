# dish-margin

Margin per dish: ingredient costs per menu item and margins in Statistik (feature dishMargin).

- Decision record: `docs/adr/ADR-J-margin-per-dish.md`; contract: `docs/build/CONTRACTS.md`
  (feature J, sections 0, 4, 5, 6.J, 9 and 12).
- Built in Run 3. No resources until Run 3: Run 0 instantiates the
  module (`dish-margin.tf`) with only `environment` and the empty `wiring` output.
- Routes: `network/api-gateway/dish-margin-routes.tf` (`local.dish_margin_routes`).
- ECR repositories already exist (`module "dish_margin_ecr"` in `config.tf`).
