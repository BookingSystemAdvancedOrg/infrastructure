# phone-agent routes (CONTRACTS.md 6.L and 12.3), created by feature-routes.tf.
# Entry: { route_key = "METHOD /path", auth = "jwt" | "public" | "operator" },
# public routes may add throttle = "public".
#
# L13/L14 (provider webhooks) are served by phone-agent-call on its Function
# URL, not listed here: feature-routes.tf sends every route of a feature to
# its one API integration (phone-agent). Reported for the hotspot window.
locals {
  phone_agent_routes = [
    { route_key = "GET /tenant/phone-agent", auth = "jwt" },
    { route_key = "PUT /tenant/phone-agent/config", auth = "jwt" },
    { route_key = "GET /locations/{locationId}/phone-agent", auth = "jwt" },
    { route_key = "PUT /locations/{locationId}/phone-agent", auth = "jwt" },
    { route_key = "POST /locations/{locationId}/phone-agent/kill-switch", auth = "jwt" },
    { route_key = "POST /locations/{locationId}/phone-agent/simulate", auth = "jwt" },
    { route_key = "GET /locations/{locationId}/phone-agent/calls", auth = "jwt" },
    { route_key = "GET /locations/{locationId}/phone-agent/calls/{callId}", auth = "jwt" },
    { route_key = "DELETE /locations/{locationId}/phone-agent/calls/{callId}/recording", auth = "jwt" },
    { route_key = "GET /locations/{locationId}/phone-agent/callbacks", auth = "jwt" },
    { route_key = "POST /locations/{locationId}/phone-agent/callbacks/{callbackId}/close", auth = "jwt" },
    { route_key = "GET /locations/{locationId}/phone-agent/reservations/{reservationId}/call", auth = "jwt" },
    # Operator routes L15-L18: Booqy Console's platform-tenants forwards them (CONTRACTS.md 9.3).
    { route_key = "GET /platform/tenants/{tenantId}/phone-agent", auth = "operator" },
    { route_key = "PUT /platform/tenants/{tenantId}/phone-agent", auth = "operator" },
    { route_key = "GET /platform/phone-agent/settings", auth = "operator" },
    { route_key = "PUT /platform/phone-agent/settings", auth = "operator" },
  ]
}
