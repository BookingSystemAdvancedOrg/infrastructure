# Cookies, sessions and security headers

What the platform stores in browsers, why no consent banner is needed, and how
the restaurant admin app's login cookie works. Each app keeps its own list of
what it stores (`storageRegistry.ts`), and its privacy page is drawn from it.

## Consent

No app sets analytics or marketing cookies. Everything stored is strictly
necessary for a service the user asked for (sign-in, cart, booking, payment,
fraud and bot protection) or a choice the user made, which is exempt from
consent under the Swedish Electronic Communications Act (LEK 9 kap. 28 §).
So there is no banner. Adding analytics or marketing storage anywhere means
adding consent first.

| App | Stores | Banner |
|---|---|---|
| booqy.se | nothing | no |
| Restaurant sites (customer-front-end) | chosen location, cart, table code, order/catering tokens (tab only); Stripe fraud cookies on the card guarantee step | no |
| Restaurant admin (admin-front-end) | refresh token in an HttpOnly cookie; chosen location; guide done | no |
| Booqy Console (booqy-console) | Amplify tokens in sessionStorage (tab only) | no |

## Admin app session

- The admin app reaches the API at `/api` on its own address. The private
  CloudFront distribution forwards `/api/*` to API Gateway (CachingDisabled,
  AllViewerExceptHostHeader) through the `api-proxy` CloudFront Function,
  which strips `/api` and adds the viewer's IP and host.
- `manage-auth` puts the refresh token in `__Secure-booqy_rt`: HttpOnly,
  Secure, SameSite=Strict, host-only, `Path=/api/auth`, 12 hours. The access
  and ID tokens (1 hour) live only in memory in the tab.
- CSRF: `/auth/refresh` and `/auth/logout` act on the cookie, so they require
  the `X-Booqy-Session: cookie` header (not allowed cross-origin by the API's
  CORS setup) and an `Origin` equal to the host the browser used. Two cookies
  with the same name (cookie tossing from a sibling subdomain) are refused.
- The viewer IP/host headers are trusted only with the `x-booqy-edge` secret,
  which CloudFront adds as an origin custom header (`random_password.cloudfront_edge`).
  Functions that apply per-IP limits get the same secret.
- SPA routing on that distribution is the `spa-routing` CloudFront Function,
  not `custom_error_response`, so the API's own 403/404 answers reach the app.

## Security headers

Response headers policies on every distribution: HSTS, nosniff, no framing,
referrer policy. Plus a full CSP on the admin app and the Console, and
`frame-ancestors 'none'` on the restaurant sites (their page CSP stays in
customer-front-end's `index.html`).

## Rollout (dev first, then the same order to prod)

1. **infrastructure**: IAM for GetTokensFromRefreshToken/RevokeToken, the edge
   secret, manage-auth's new env vars, CloudFront `/api` and headers, refresh
   token validity 12 h. Rotation stays off.
2. **application**: the manage-auth release. Its new version picks up the env
   vars from step 1.
3. **admin-front-end**: switches to `/api` and the cookie. Everyone signs in
   once more (old sessions in localStorage are removed).
4. **infrastructure**, later: set `refresh_token_rotation_enabled = true` in the
   environment's tfvars and apply. That turns on rotation and removes
   `ALLOW_REFRESH_TOKEN_AUTH` from the staff app client. Do not do this before
   step 2 is live in that environment: the old manage-auth refreshes with
   `REFRESH_TOKEN_AUTH`, which Cognito refuses once rotation is on.

Older admin builds keep working through steps 1 and 2 (they use the legacy
body-based refresh against API Gateway directly).
