# help-assistant routes (in-app help chatbot in Booqy Admin), created by feature-routes.tf.
# Entry: { route_key = "METHOD /path", auth = "jwt" | "public" | "operator" },
# public routes may add throttle = "public".
locals {
  help_assistant_routes = [
    { route_key = "GET /tenant/help-assistant", auth = "jwt" },
    { route_key = "POST /tenant/help-assistant/answers", auth = "jwt" },
  ]
}
