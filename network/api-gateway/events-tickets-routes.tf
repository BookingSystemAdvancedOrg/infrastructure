# events-tickets routes (CONTRACTS.md 6.K and 12.3), created by feature-routes.tf.
# Entry: { route_key = "METHOD /path", auth = "jwt" | "public" | "operator" },
# public routes may add throttle = "public".
locals {
  events_tickets_routes = [
    { route_key = "GET /locations/{locationId}/events", auth = "jwt" },
    { route_key = "POST /locations/{locationId}/events", auth = "jwt" },
    { route_key = "GET /locations/{locationId}/events/{eventId}", auth = "jwt" },
    { route_key = "PUT /locations/{locationId}/events/{eventId}", auth = "jwt" },
    { route_key = "POST /locations/{locationId}/events/{eventId}/publish", auth = "jwt" },
    { route_key = "PUT /locations/{locationId}/events/{eventId}/ticket-types/{typeId}", auth = "jwt" },
    { route_key = "DELETE /locations/{locationId}/events/{eventId}/ticket-types/{typeId}", auth = "jwt" },
    { route_key = "PUT /locations/{locationId}/events/{eventId}/occurrences/{occurrenceId}", auth = "jwt" },
    { route_key = "POST /locations/{locationId}/events/{eventId}/occurrences/{occurrenceId}/cancel", auth = "jwt" },
    { route_key = "GET /locations/{locationId}/events/{eventId}/occurrences/{occurrenceId}/guest-list", auth = "jwt" },
    { route_key = "POST /locations/{locationId}/events/{eventId}/occurrences/{occurrenceId}/check-ins", auth = "jwt" },
    { route_key = "GET /locations/{locationId}/events/{eventId}/orders", auth = "jwt" },
    { route_key = "POST /locations/{locationId}/events/tickets/{ticketId}/refund", auth = "jwt" },
    { route_key = "GET /locations/{locationId}/events/jobs/{jobId}", auth = "jwt" },
    { route_key = "GET /public/locations/{locationId}/events", auth = "public", throttle = "public" },
    { route_key = "GET /public/locations/{locationId}/events/{eventId}", auth = "public", throttle = "public" },
    { route_key = "POST /public/locations/{locationId}/events/checkout", auth = "public", throttle = "public" },
    { route_key = "GET /public/tickets/{token}", auth = "public", throttle = "public" },
    { route_key = "GET /public/tickets/{token}/pass", auth = "public", throttle = "public" },
    { route_key = "POST /public/tickets/{token}/transfers", auth = "public", throttle = "public" },
    { route_key = "POST /public/ticket-transfers/{transferToken}/accept", auth = "public", throttle = "public" },
    { route_key = "DELETE /public/tickets/{token}/transfers/{transferId}", auth = "public", throttle = "public" },
  ]
}
