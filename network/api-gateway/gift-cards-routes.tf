# gift-cards routes (CONTRACTS.md 6.E and 12.3), created by feature-routes.tf.
# Entry: { route_key = "METHOD /path", auth = "jwt" | "public" | "operator" },
# public routes may add throttle = "public".
locals {
  gift_cards_routes = []
}
