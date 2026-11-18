# tenant-setup routes (Kom igång in Booqy Admin, owner only), created by feature-routes.tf.
# Entry: { route_key = "METHOD /path", auth = "jwt" | "public" | "operator" },
# public routes may add throttle = "public".
locals {
  tenant_setup_routes = [
    { route_key = "GET /tenant/setup", auth = "jwt" },
    { route_key = "PUT /tenant/setup/skips", auth = "jwt" },
  ]
}
