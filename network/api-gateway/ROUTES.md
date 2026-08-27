<!-- GENERATED FILE - do not hand-edit. Run `python3 generate_routes.py` -->
<!-- after changing routes in main.tf to bring this back in sync.        -->

# HTTP API routes

One row per route defined in `main.tf`. `Auth` is `NONE` (no token required)
or `JWT` (must present a valid Cognito access token in the `Authorization`
header, validated by the `cognito` authorizer).

| Method | Path | Auth | Lambda |
|---|---|---|---|
| GET | `/locations/{locationId}` | JWT | get-location |
| POST | `/locations` | JWT | create-location |
| PUT | `/locations/{locationId}` | JWT | create-location |
| GET | `/locations/{locationId}/menu` | NONE | get-menu |
| POST | `/locations/{locationId}/menu/{proxy+}` | JWT | manage-menu |
| PUT | `/locations/{locationId}/menu/{proxy+}` | JWT | manage-menu |
| DELETE | `/locations/{locationId}/menu/{proxy+}` | JWT | manage-menu |
| GET | `/locations/{locationId}/availability` | NONE | get-availability |
| POST | `/reservations` | NONE | create-pending-reservation |
| GET | `/reservations/{reservationId}` | JWT | get-reservation |
| POST | `/reservations/{reservationId}/cancel` | NONE | cancel-reservation |
| POST | `/reservations/{reservationId}/arrive` | JWT | mark-arrived |
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
| GET | `/menu-images/presigned-url` | JWT | pre-signed-url |
