# meta-ads routes (CONTRACTS.md 6.A and 12.3), created by feature-routes.tf.
# Entry: { route_key = "METHOD /path", auth = "jwt" | "public" | "operator" },
# public routes may add throttle = "public".
locals {
  meta_ads_routes = []
}
