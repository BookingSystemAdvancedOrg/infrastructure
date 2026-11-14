# meta-ads routes (CONTRACTS.md 6.A and 12.3), created by feature-routes.tf.
# Entry: { route_key = "METHOD /path", auth = "jwt" | "public" | "operator" },
# public routes may add throttle = "public".
locals {
  meta_ads_routes = [
    { route_key = "GET /tenant/meta-ads/connection", auth = "jwt" },
    { route_key = "POST /tenant/meta-ads/connection/start", auth = "jwt" },
    { route_key = "POST /tenant/meta-ads/connection/callback", auth = "jwt" },
    { route_key = "GET /tenant/meta-ads/assets", auth = "jwt" },
    { route_key = "PUT /tenant/meta-ads/connection", auth = "jwt" },
    { route_key = "DELETE /tenant/meta-ads/connection", auth = "jwt" },
    { route_key = "POST /locations/{locationId}/meta-ads/copy", auth = "jwt" },
    { route_key = "POST /locations/{locationId}/meta-ads/campaigns", auth = "jwt" },
    { route_key = "GET /locations/{locationId}/meta-ads/campaigns", auth = "jwt" },
    { route_key = "GET /locations/{locationId}/meta-ads/campaigns/{campaignId}", auth = "jwt" },
    { route_key = "POST /locations/{locationId}/meta-ads/campaigns/{campaignId}/activate", auth = "jwt" },
    { route_key = "POST /locations/{locationId}/meta-ads/campaigns/{campaignId}/pause", auth = "jwt" },
    { route_key = "GET /locations/{locationId}/meta-ads/insights", auth = "jwt" },
    # Operator routes A14-A17: Booqy Console's platform-tenants forwards them (CONTRACTS.md 9.3).
    { route_key = "GET /platform/meta-ads/settings", auth = "operator" },
    { route_key = "PUT /platform/meta-ads/settings", auth = "operator" },
    { route_key = "PUT /platform/tenants/{tenantId}/meta-ads", auth = "operator" },
    { route_key = "GET /platform/tenants/{tenantId}/meta-ads", auth = "operator" },
  ]
}
