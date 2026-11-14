# personalliggare routes (CONTRACTS.md 6.H and 12.3), created by feature-routes.tf.
# Entry: { route_key = "METHOD /path", auth = "jwt" | "public" | "operator" },
# public routes may add throttle = "public".
locals {
  personalliggare_routes = [
    { route_key = "GET /locations/{locationId}/personalliggare", auth = "jwt" },
    { route_key = "POST /locations/{locationId}/personalliggare/check-in", auth = "jwt" },
    { route_key = "POST /locations/{locationId}/personalliggare/check-out", auth = "jwt" },
    { route_key = "POST /locations/{locationId}/personalliggare/corrections", auth = "jwt" },
    { route_key = "GET /locations/{locationId}/personalliggare/inspection", auth = "jwt" },
    { route_key = "GET /locations/{locationId}/personalliggare/export", auth = "jwt" },
    { route_key = "GET /tenant/personalliggare/persons", auth = "jwt" },
    { route_key = "PUT /tenant/personalliggare/persons/{personId}", auth = "jwt" },
    # Operator route H9: Booqy Console's platform-tenants forwards it (CONTRACTS.md 9.3).
    { route_key = "GET /platform/tenants/{tenantId}/personalliggare/export", auth = "operator" },
  ]
}
