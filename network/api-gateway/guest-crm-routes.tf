# guest-crm routes (CONTRACTS.md 6.C and 12.3), created by feature-routes.tf.
# Entry: { route_key = "METHOD /path", auth = "jwt" | "public" | "operator" },
# public routes may add throttle = "public".
locals {
  guest_crm_routes = []
}
