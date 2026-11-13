# user-backdrop routes (own background image per user in Booqy Admin), created by feature-routes.tf.
# Entry: { route_key = "METHOD /path", auth = "jwt" | "public" | "operator" },
# public routes may add throttle = "public".
locals {
  user_backdrop_routes = [
    { route_key = "GET /me/backdrop", auth = "jwt" },
    { route_key = "POST /me/backdrop/upload", auth = "jwt" },
    { route_key = "DELETE /me/backdrop", auth = "jwt" },
  ]
}
