"""Run: python3 -m unittest discover -s compute/lambda/pre-token-generation/tests"""

import os
import sys
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "src"))

import handler  # noqa: E402


def event(tenant_id="t_123", groups=("staff_user",)):
    attributes = {"sub": "abc", "email": "a@example.se"}
    if tenant_id is not None:
        attributes["custom:tenant_id"] = tenant_id
    return {
        "version": "2",
        "triggerSource": "TokenGeneration_Authentication",
        "userName": "abc",
        "request": {
            "userAttributes": attributes,
            "groupConfiguration": {"groupsToOverride": list(groups)},
            "scopes": ["aws.cognito.signin.user.admin"],
        },
        "response": {"claimsAndScopeOverrideDetails": None},
    }


class PreTokenGenerationTest(unittest.TestCase):
    def claims(self, result, token):
        return result["response"]["claimsAndScopeOverrideDetails"][token]["claimsToAddOrOverride"]

    def test_staff_gets_tenant_and_role_in_both_tokens(self):
        result = handler.handler(event(), None)
        for token in ("idTokenGeneration", "accessTokenGeneration"):
            self.assertEqual(self.claims(result, token), {"tenant_id": "t_123", "role": "staff_user"})

    def test_owner_wins_over_staff(self):
        result = handler.handler(event(groups=("staff_user", "owner_user")), None)
        self.assertEqual(self.claims(result, "accessTokenGeneration")["role"], "owner_user")

    def test_missing_tenant_refuses_tokens(self):
        with self.assertRaises(handler.AccountNotProvisioned):
            handler.handler(event(tenant_id=None), None)

    def test_blank_tenant_refuses_tokens(self):
        with self.assertRaises(handler.AccountNotProvisioned):
            handler.handler(event(tenant_id="   "), None)

    def test_no_role_group_refuses_tokens(self):
        with self.assertRaises(handler.AccountNotProvisioned):
            handler.handler(event(groups=()), None)

    def test_unrelated_group_is_not_a_role(self):
        with self.assertRaises(handler.AccountNotProvisioned):
            handler.handler(event(groups=("super_user",)), None)

    def test_error_message_does_not_leak_details(self):
        with self.assertRaises(handler.AccountNotProvisioned) as ctx:
            handler.handler(event(tenant_id=None), None)
        self.assertNotIn("tenant_id", str(ctx.exception))

    def test_refresh_trigger_is_handled_the_same(self):
        e = event()
        e["triggerSource"] = "TokenGeneration_RefreshTokens"
        result = handler.handler(e, None)
        self.assertEqual(self.claims(result, "idTokenGeneration")["tenant_id"], "t_123")


if __name__ == "__main__":
    unittest.main()
