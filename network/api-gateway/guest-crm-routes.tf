# guest-crm routes (CONTRACTS.md 6.C and 12.3), created by feature-routes.tf.
# Entry: { route_key = "METHOD /path", auth = "jwt" | "public" | "operator" },
# public routes may add throttle = "public".
locals {
  guest_crm_routes = [
    { route_key = "GET /tenant/guests", auth = "jwt" },
    { route_key = "POST /tenant/guests/search", auth = "jwt" },
    { route_key = "GET /tenant/guests/{guestId}", auth = "jwt" },
    { route_key = "PATCH /tenant/guests/{guestId}", auth = "jwt" },
    { route_key = "POST /locations/{locationId}/guests/lookup", auth = "jwt" },
    { route_key = "GET /tenant/guest-segments", auth = "jwt" },
    { route_key = "PUT /tenant/guest-segments/{segmentId}", auth = "jwt" },
    { route_key = "DELETE /tenant/guest-segments/{segmentId}", auth = "jwt" },
    { route_key = "GET /tenant/guest-segments/{segmentId}/preview", auth = "jwt" },
    { route_key = "POST /tenant/guest-segments/{segmentId}/exports", auth = "jwt" },
    { route_key = "POST /tenant/guests/rebuild", auth = "jwt" },
  ]
}
