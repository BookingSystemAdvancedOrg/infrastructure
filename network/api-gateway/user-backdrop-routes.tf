# user-backdrop routes (background image library and profile picture in Booqy Admin), created by feature-routes.tf.
# Entry: { route_key = "METHOD /path", auth = "jwt" | "public" | "operator" },
# public routes may add throttle = "public".
locals {
  user_backdrop_routes = [
    { route_key = "GET /me/backdrops", auth = "jwt" },
    { route_key = "POST /me/backdrops/upload", auth = "jwt" },
    { route_key = "POST /me/backdrops/{id}/complete", auth = "jwt" },
    { route_key = "PUT /me/backdrops/selected", auth = "jwt" },
    { route_key = "DELETE /me/backdrops/{id}", auth = "jwt" },
    # Optional profile picture (admin/<tenantId>/<sub>/avatar.webp)
    { route_key = "GET /me/avatar", auth = "jwt" },
    { route_key = "POST /me/avatar/upload", auth = "jwt" },
    { route_key = "POST /me/avatar/complete", auth = "jwt" },
    { route_key = "DELETE /me/avatar", auth = "jwt" },
  ]
}
