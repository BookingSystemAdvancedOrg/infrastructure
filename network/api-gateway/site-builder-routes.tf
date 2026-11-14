# site-builder routes (CONTRACTS.md 6.B and 12.3), created by feature-routes.tf.
# Entry: { route_key = "METHOD /path", auth = "jwt" | "public" | "operator" },
# public routes may add throttle = "public".
# B9-B13 (AI edits, custom-code tier) are added with B2 in Run 2.
locals {
  site_builder_routes = [
    { route_key = "GET /tenant/site-builder", auth = "jwt" },
    { route_key = "PUT /tenant/site-builder/draft", auth = "jwt" },
    { route_key = "POST /tenant/site-builder/preview-links", auth = "jwt" },
    { route_key = "POST /tenant/site-builder/publish", auth = "jwt" },
    { route_key = "GET /tenant/site-builder/publish/{publishId}", auth = "jwt" },
    { route_key = "GET /tenant/site-builder/versions", auth = "jwt" },
    { route_key = "POST /tenant/site-builder/rollback", auth = "jwt" },
    { route_key = "POST /public/site-builder/preview", auth = "public", throttle = "public" },
  ]
}
