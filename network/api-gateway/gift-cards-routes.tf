# gift-cards routes (CONTRACTS.md 6.E and 12.3), created by feature-routes.tf.
# Entry: { route_key = "METHOD /path", auth = "jwt" | "public" | "operator" },
# public routes may add throttle = "public".
locals {
  gift_cards_routes = [
    { route_key = "GET /public/locations/{locationId}/gift-cards/offer", auth = "public", throttle = "public" },
    { route_key = "POST /public/locations/{locationId}/gift-cards/checkout", auth = "public", throttle = "public" },
    { route_key = "POST /public/locations/{locationId}/gift-cards/balance", auth = "public", throttle = "public" },
    { route_key = "GET /tenant/gift-cards/settings", auth = "jwt" },
    { route_key = "PUT /tenant/gift-cards/settings", auth = "jwt" },
    { route_key = "GET /tenant/gift-cards", auth = "jwt" },
    { route_key = "GET /tenant/gift-cards/{cardId}", auth = "jwt" },
    { route_key = "POST /tenant/gift-cards/{cardId}/adjust", auth = "jwt" },
    { route_key = "POST /tenant/gift-cards/{cardId}/refund", auth = "jwt" },
    { route_key = "POST /tenant/gift-cards/{cardId}/resend", auth = "jwt" },
    { route_key = "POST /locations/{locationId}/gift-cards/lookup", auth = "jwt" },
    { route_key = "POST /locations/{locationId}/gift-cards/redemptions", auth = "jwt" },
    { route_key = "POST /locations/{locationId}/gift-cards/redemptions/{txId}/reverse", auth = "jwt" },
  ]
}
