# user-backdrop routes (personal background image library in Booqy Admin), created by feature-routes.tf.
# Entry: { route_key = "METHOD /path", auth = "jwt" | "public" | "operator" },
# public routes may add throttle = "public".
locals {
  user_backdrop_routes = [
    { route_key = "GET /me/backdrops", auth = "jwt" },
    { route_key = "POST /me/backdrops/upload", auth = "jwt" },
    { route_key = "POST /me/backdrops/{id}/complete", auth = "jwt" },
    { route_key = "PUT /me/backdrops/selected", auth = "jwt" },
    { route_key = "DELETE /me/backdrops/{id}", auth = "jwt" },
  ]
}
