"""Cognito pre token generation trigger (event version 2) - tenant user pool.

Puts the caller's tenant and role into BOTH the ID token and the access token:

    tenant_id - the user's immutable custom:tenant_id attribute, set once by
                AdminCreateUser (onboarding workflow / manage-user) and not
                writable by the app client, so a user can never move
                themselves to another tenant
    role      - owner_user | staff_user, from the user's Cognito groups

API Gateway's JWT authorizer validates the token; every Lambda then reads
tenant_id from the claims (never from the request body, path or a header)
and checks that the {locationId} it was called with belongs to that tenant.

A user without a tenant or without a tenant role gets NO token at all:
raising here makes Cognito fail the sign-in / refresh, so a half-provisioned
or misconfigured account can never reach the API with a token that carries
no tenant.

Infra-owned and deployed as a zip by Terraform (compute/lambda/pre-token-
generation), not through the backend image pipeline: a placeholder image in
this trigger would break every login.
"""

# Highest privilege first - a user in both groups is treated as an owner.
ROLE_PRECEDENCE = ("owner_user", "staff_user")


class AccountNotProvisioned(Exception):
    """Raised to make Cognito refuse to issue tokens.

    The message reaches the client inside Cognito's error, so it is
    deliberately generic - the specific reason only goes to the logs.
    """


def handler(event, context):
    request = event.get("request") or {}
    attributes = request.get("userAttributes") or {}
    groups = (request.get("groupConfiguration") or {}).get("groupsToOverride") or []

    tenant_id = (attributes.get("custom:tenant_id") or "").strip()
    role = next((r for r in ROLE_PRECEDENCE if r in groups), None)

    if not tenant_id or role is None:
        print(
            "refusing tokens: user=%s tenant_id_present=%s role=%s trigger=%s"
            % (event.get("userName"), bool(tenant_id), role, event.get("triggerSource"))
        )
        raise AccountNotProvisioned("account not provisioned for any tenant")

    claims = {"tenant_id": tenant_id, "role": role}
    response = event.setdefault("response", {})
    response["claimsAndScopeOverrideDetails"] = {
        "idTokenGeneration": {"claimsToAddOrOverride": claims},
        "accessTokenGeneration": {"claimsToAddOrOverride": claims},
    }
    return event
