<!-- GENERATED FILE - do not hand-edit. Run `python3 generate_routes.py` -->
<!-- after changing routes in main.tf to bring this back in sync.        -->

# HTTP API routes

One row per route defined in `main.tf`. `Auth` is `NONE` (no token required),
`JWT` (a valid access token from the TENANT user pool in the `Authorization`
header, validated by the `cognito` authorizer; the Lambda then checks the
token's tenant_id against the resource) or `JWT (operator)` (an access token
from the OPERATOR user pool with the `platform/admin` scope, validated by the
`platform` authorizer).

| Method | Path | Auth | Lambda |
|---|---|---|---|
| GET | `/locations/{locationId}` | JWT | get-location |
| GET | `/locations` | JWT | get-location |
| POST | `/locations` | JWT | create-location |
| PUT | `/locations/{locationId}` | JWT | create-location |
| GET | `/locations/{locationId}/menu` | NONE | get-menu |
| POST | `/locations/{locationId}/menu/{proxy+}` | JWT | manage-menu |
| PUT | `/locations/{locationId}/menu/{proxy+}` | JWT | manage-menu |
| DELETE | `/locations/{locationId}/menu/{proxy+}` | JWT | manage-menu |
| GET | `/locations/{locationId}/availability` | NONE | get-availability |
| POST | `/order` | NONE | payment-intent |
| POST | `/locations/{locationId}/reservations/{reservationId}/cancel` | NONE | cancel-reservation |
| POST | `/locations/{locationId}/reservations/{reservationId}/status` | JWT | mark-arrived |
| PATCH | `/locations/{locationId}/reservations/{reservationId}` | JWT | mark-arrived |
| POST | `/locations/{locationId}/reservations/{reservationId}/payment` | JWT | mark-arrived |
| POST | `/locations/{locationId}/tables/{tableId}/block` | JWT | block-table |
| GET | `/locations/{locationId}/layout-elements/{proxy+}` | JWT | manage-layout-element |
| POST | `/locations/{locationId}/layout-elements/{proxy+}` | JWT | manage-layout-element |
| PUT | `/locations/{locationId}/layout-elements/{proxy+}` | JWT | manage-layout-element |
| DELETE | `/locations/{locationId}/layout-elements/{proxy+}` | JWT | manage-layout-element |
| POST | `/locations/{locationId}/layout/publish` | JWT | publish-layout |
| GET | `/locations/{locationId}/layout/versions` | JWT | list-layout-version |
| POST | `/locations/{locationId}/layout/versions/{versionId}/activate` | JWT | activate-layout-version |
| POST | `/auth/{proxy+}` | NONE | manage-auth |
| GET | `/users/{proxy+}` | JWT | manage-user |
| POST | `/users/{proxy+}` | JWT | manage-user |
| PUT | `/users/{proxy+}` | JWT | manage-user |
| DELETE | `/users/{proxy+}` | JWT | manage-user |
| GET | `/list-users` | JWT | list-users |
| GET | `/menu-images/presigned-url` | JWT | pre-signed-url |
| GET | `/locations/{locationId}/orders` | JWT | manage-order |
| POST | `/locations/{locationId}/orders` | JWT | manage-order |
| PUT | `/locations/{locationId}/orders` | JWT | manage-order |
| DELETE | `/locations/{locationId}/orders` | JWT | manage-order |
| GET | `/locations/{locationId}/catering/settings` | NONE | catering-settings |
| PUT | `/locations/{locationId}/catering/settings` | JWT | catering-settings |
| GET | `/locations/{locationId}/catering/discount-tiers` | NONE | catering-discount-tiers |
| POST | `/locations/{locationId}/catering/discount-tiers` | JWT | catering-discount-tiers |
| PUT | `/locations/{locationId}/catering/discount-tiers/{tierId}` | JWT | catering-discount-tiers |
| DELETE | `/locations/{locationId}/catering/discount-tiers/{tierId}` | JWT | catering-discount-tiers |
| POST | `/locations/{locationId}/catering/requests` | NONE | catering-requests |
| GET | `/locations/{locationId}/catering/requests` | JWT | catering-requests |
| GET | `/locations/{locationId}/catering/requests/{requestId}` | JWT | catering-offer |
| GET | `/locations/{locationId}/catering/requests/{requestId}/documents/{docId}` | JWT | catering-offer |
| PUT | `/locations/{locationId}/catering/requests/{requestId}/offer` | JWT | catering-offer |
| POST | `/locations/{locationId}/catering/requests/{requestId}/offer/send` | JWT | catering-offer |
| POST | `/locations/{locationId}/catering/requests/{requestId}/decline` | JWT | catering-offer |
| POST | `/locations/{locationId}/catering/requests/{requestId}/cancel` | JWT | catering-offer |
| POST | `/locations/{locationId}/catering/requests/{requestId}/delivered` | JWT | catering-offer |
| GET | `/locations/{locationId}/catering/invoices` | JWT | catering-offer |
| POST | `/locations/{locationId}/catering/invoices/{invoiceId}/mark-paid` | JWT | catering-offer |
| GET | `/locations/{locationId}/catering/requests/{requestId}/customer` | NONE | catering-customer |
| POST | `/locations/{locationId}/catering/requests/{requestId}/customer/sign` | NONE | catering-customer |
| POST | `/locations/{locationId}/catering/requests/{requestId}/customer/checkout` | NONE | catering-customer |
| GET | `/locations/{locationId}/catering/requests/{requestId}/customer/documents/{docId}` | NONE | catering-customer |
| POST | `/webhooks/signing/catering` | NONE | catering-signing-webhook |
| GET | `/platform/plans` | JWT (operator) | platform-tenants |
| GET | `/platform/tenants` | JWT (operator) | platform-tenants |
| POST | `/platform/tenants` | JWT (operator) | platform-tenants |
| GET | `/platform/tenants/{tenantId}` | JWT (operator) | platform-tenants |
| PATCH | `/platform/tenants/{tenantId}` | JWT (operator) | platform-tenants |
| PUT | `/platform/tenants/{tenantId}/plan` | JWT (operator) | platform-tenants |
| POST | `/platform/tenants/{tenantId}/suspend` | JWT (operator) | platform-tenants |
| POST | `/platform/tenants/{tenantId}/resume` | JWT (operator) | platform-tenants |
| POST | `/platform/tenants/{tenantId}/offboard` | JWT (operator) | platform-tenants |
| POST | `/platform/tenants/{tenantId}/purge` | JWT (operator) | platform-tenants |
| POST | `/platform/tenants/{tenantId}/onboarding/retry` | JWT (operator) | platform-tenants |
| GET | `/platform/tenants/{tenantId}/users` | JWT (operator) | platform-tenants |
| POST | `/platform/tenants/{tenantId}/owners` | JWT (operator) | platform-tenants |
| GET | `/platform/tenants/{tenantId}/locations` | JWT (operator) | platform-tenants |
| POST | `/platform/tenants/{tenantId}/locations` | JWT (operator) | platform-tenants |
| PATCH | `/platform/tenants/{tenantId}/locations/{locationId}` | JWT (operator) | platform-tenants |
| DELETE | `/platform/tenants/{tenantId}/locations/{locationId}` | JWT (operator) | platform-tenants |
| POST | `/platform/tenants/{tenantId}/domains` | JWT (operator) | platform-tenants |
| DELETE | `/platform/tenants/{tenantId}/domains/{domain}` | JWT (operator) | platform-tenants |
| GET | `/platform/domains/search` | JWT (operator) | platform-tenants |
| GET | `/platform/domains/dns-scan` | JWT (operator) | platform-tenants |
| POST | `/platform/tenants/{tenantId}/domains/documents` | JWT (operator) | platform-tenants |
| POST | `/platform/tenants/{tenantId}/domains/registrations` | JWT (operator) | platform-tenants |
| POST | `/platform/tenants/{tenantId}/domains/connections` | JWT (operator) | platform-tenants |
| GET | `/platform/tenants/{tenantId}/zones/{domain}/document` | JWT (operator) | platform-tenants |
| GET | `/platform/tenants/{tenantId}/zones/{domain}/transfer` | JWT (operator) | platform-tenants |
| POST | `/platform/tenants/{tenantId}/zones/{domain}/transfer` | JWT (operator) | platform-tenants |
| POST | `/platform/tenants/{tenantId}/stripe/account-link` | JWT (operator) | platform-tenants |
| POST | `/platform/tenants/{tenantId}/stripe/sync` | JWT (operator) | platform-tenants |
| GET | `/platform/tenants/{tenantId}/locations/{locationId}/terminal` | JWT (operator) | platform-tenants |
| POST | `/platform/tenants/{tenantId}/locations/{locationId}/terminal` | JWT (operator) | platform-tenants |
| PATCH | `/platform/tenants/{tenantId}/locations/{locationId}/terminal` | JWT (operator) | platform-tenants |
| POST | `/platform/tenants/{tenantId}/locations/{locationId}/terminal/readers` | JWT (operator) | platform-tenants |
| DELETE | `/platform/tenants/{tenantId}/locations/{locationId}/terminal/readers/{readerId}` | JWT (operator) | platform-tenants |
| GET | `/platform/operators` | JWT (operator) | platform-tenants |
| POST | `/platform/operators` | JWT (operator) | platform-tenants |
| PATCH | `/platform/operators/{username}` | JWT (operator) | platform-tenants |
| DELETE | `/platform/operators/{username}` | JWT (operator) | platform-tenants |
| POST | `/platform/operators/{username}/resend-invite` | JWT (operator) | platform-tenants |
| GET | `/platform/outbox` | JWT (operator) | platform-tenants |
| GET | `/platform/outbox/{messageId}` | JWT (operator) | platform-tenants |
| GET | `/platform/mail/template` | JWT (operator) | platform-tenants |
| PUT | `/platform/mail/template` | JWT (operator) | platform-tenants |
| POST | `/platform/mail/preview` | JWT (operator) | platform-tenants |
| GET | `/platform/mail/recipients` | JWT (operator) | platform-tenants |
| GET | `/platform/mail/newsletters` | JWT (operator) | platform-tenants |
| POST | `/platform/mail/newsletters` | JWT (operator) | platform-tenants |
| GET | `/platform/mail/newsletters/{newsletterId}` | JWT (operator) | platform-tenants |
| GET | `/platform/finance/overview` | JWT (operator) | platform-tenants |
| GET | `/platform/finance/tenants/{tenantId}` | JWT (operator) | platform-tenants |
| POST | `/platform/finance/rebuild` | JWT (operator) | platform-tenants |
| POST | `/platform/finance/stripe-sync` | JWT (operator) | platform-tenants |
| GET | `/platform/tenants/{tenantId}/billing` | JWT (operator) | platform-tenants |
| POST | `/platform/tenants/{tenantId}/billing/subscription` | JWT (operator) | platform-tenants |
| PATCH | `/platform/tenants/{tenantId}/billing/subscription` | JWT (operator) | platform-tenants |
| POST | `/platform/tenants/{tenantId}/billing/card-link` | JWT (operator) | platform-tenants |
| POST | `/platform/tenants/{tenantId}/billing/invoices/{invoiceId}/remind` | JWT (operator) | platform-tenants |
| GET | `/platform/finance/invoices` | JWT (operator) | platform-tenants |
| GET | `/tenant` | JWT | tenant-account |
| PATCH | `/tenant` | JWT | tenant-account |
| POST | `/tenant/stripe/account-link` | JWT | tenant-account |
| GET | `/insights` | JWT | insights |
| GET | `/site-config` | NONE | tenant-site-config |
| GET | `/marketing/{proxy+}` | JWT | marketing |
| POST | `/marketing/{proxy+}` | JWT | marketing |
| PUT | `/marketing/{proxy+}` | JWT | marketing |
| DELETE | `/marketing/{proxy+}` | JWT | marketing |
| POST | `/t` | NONE | marketing-public |
| GET | `/m/c/{token}` | NONE | marketing-public |
| GET | `/m/u/{token}` | NONE | marketing-public |
| POST | `/m/u/{token}` | NONE | marketing-public |
| GET | `/m/offer` | NONE | marketing-public |
| POST | `/m/signup` | NONE | marketing-public |
| POST | `/m/code` | NONE | marketing-public |
| GET | `/m/s/{token}` | NONE | marketing-public |
| POST | `/m/s/{token}` | NONE | marketing-public |
