# support-reports routes ("Rapportera till Booqy" in Booqy Admin), created by feature-routes.tf.
# Entry: { route_key = "METHOD /path", auth = "jwt" | "public" | "operator" },
# public routes may add throttle = "public".
locals {
  support_reports_routes = [
    { route_key = "POST /tenant/support/reports", auth = "jwt" },
  ]
}
