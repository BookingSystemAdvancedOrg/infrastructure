# site-translate route (restaurant sites' language switcher), created by feature-routes.tf.
# Public: the site reaches it as /api/translate through its CloudFront and the AWS WAF.
# Entry: { route_key = "METHOD /path", auth = "jwt" | "public" | "operator" },
# public routes may add throttle = "public".
locals {
  site_translate_routes = [
    { route_key = "POST /translate", auth = "public", throttle = "public" },
  ]
}
