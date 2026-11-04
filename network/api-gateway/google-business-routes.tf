# google-business routes (CONTRACTS.md 6.D and 12.3), created by feature-routes.tf.
# Entry: { route_key = "METHOD /path", auth = "jwt" | "public" | "operator" },
# public routes may add throttle = "public".
locals {
  google_business_routes = [
    { route_key = "GET /tenant/google-business/connection", auth = "jwt" },
    { route_key = "POST /tenant/google-business/connection/start", auth = "jwt" },
    { route_key = "POST /tenant/google-business/connection/callback", auth = "jwt" },
    { route_key = "DELETE /tenant/google-business/connection", auth = "jwt" },
    { route_key = "GET /tenant/google-business/locations", auth = "jwt" },
    { route_key = "GET /locations/{locationId}/google-business", auth = "jwt" },
    { route_key = "PUT /locations/{locationId}/google-business/link", auth = "jwt" },
    { route_key = "DELETE /locations/{locationId}/google-business/link", auth = "jwt" },
    { route_key = "POST /locations/{locationId}/google-business/sync", auth = "jwt" },
    { route_key = "PUT /locations/{locationId}/google-business/review-settings", auth = "jwt" },
    # Operator route D11: Booqy Console's platform-tenants forwards it (CONTRACTS.md 9.3).
    { route_key = "GET /platform/tenants/{tenantId}/google-business", auth = "operator" },
  ]
}
