# social-posting routes (CONTRACTS.md 6.G and 12.3), created by feature-routes.tf.
# Entry: { route_key = "METHOD /path", auth = "jwt" | "public" | "operator" },
# public routes may add throttle = "public".
locals {
  social_posting_routes = [
    { route_key = "GET /tenant/social-posts", auth = "jwt" },
    { route_key = "POST /tenant/social-posts", auth = "jwt" },
    { route_key = "POST /tenant/social-posts/drafts", auth = "jwt" },
    { route_key = "GET /tenant/social-posts/{postId}", auth = "jwt" },
    { route_key = "PUT /tenant/social-posts/{postId}", auth = "jwt" },
    { route_key = "POST /tenant/social-posts/{postId}/schedule", auth = "jwt" },
    { route_key = "POST /tenant/social-posts/{postId}/cancel", auth = "jwt" },
    { route_key = "DELETE /tenant/social-posts/{postId}", auth = "jwt" },
  ]
}
