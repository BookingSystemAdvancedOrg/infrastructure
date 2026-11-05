# waitlist routes (CONTRACTS.md 6.F and 12.3), created by feature-routes.tf.
# Entry: { route_key = "METHOD /path", auth = "jwt" | "public" | "operator" },
# public routes may add throttle = "public".
locals {
  waitlist_routes = [
    { route_key = "GET /locations/{locationId}/waitlist", auth = "jwt" },
    { route_key = "POST /locations/{locationId}/waitlist", auth = "jwt" },
    { route_key = "POST /locations/{locationId}/waitlist/{entryId}/offer", auth = "jwt" },
    { route_key = "POST /locations/{locationId}/waitlist/{entryId}/seat", auth = "jwt" },
    { route_key = "POST /locations/{locationId}/waitlist/{entryId}/remove", auth = "jwt" },
    { route_key = "PUT /locations/{locationId}/waitlist/settings", auth = "jwt" },
    { route_key = "POST /public/locations/{locationId}/waitlist", auth = "public", throttle = "public" },
    { route_key = "GET /public/waitlist/{token}", auth = "public", throttle = "public" },
    { route_key = "POST /public/waitlist/{token}/accept", auth = "public", throttle = "public" },
    { route_key = "POST /public/waitlist/{token}/leave", auth = "public", throttle = "public" },
  ]
}
