# help-assistant tenant routes (help assistant in Booqy Admin), created by feature-routes.tf.
# Booqy Console uses the operator routes in help-assistant-operator-routes.tf.
# Entry: { route_key = "METHOD /path", auth = "jwt" | "public" | "operator" },
# public routes may add throttle = "public".
locals {
  help_assistant_routes = [
    { route_key = "GET /tenant/help-assistant", auth = "jwt" },
    { route_key = "POST /tenant/help-assistant/answers", auth = "jwt" },
  ]
}
