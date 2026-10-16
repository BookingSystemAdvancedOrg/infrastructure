"""Run: python3 -m unittest discover -s compute/lambda/cognito-custom-message/tests"""

import os
import sys
import unittest
from unittest import mock

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "src"))

import handler  # noqa: E402

RESET_URL = "https://app.example.se/aterstall-losenord"


def event(trigger="CustomMessage_ForgotPassword", email="anna@example.se", code="{####}"):
    attributes = {"sub": "abc", "email_verified": "true"}
    if email is not None:
        attributes["email"] = email
    return {
        "version": "1",
        "triggerSource": trigger,
        "userName": "abc",
        "request": {
            "userAttributes": attributes,
            "codeParameter": code,
            "usernameParameter": None,
        },
        "response": {"smsMessage": None, "emailMessage": None, "emailSubject": None},
    }


def run(e, language="sv", url=RESET_URL):
    env = {"LANGUAGE": language, "RESET_URL": url}
    with mock.patch.dict(os.environ, env, clear=False):
        return handler.handler(e, None)


class ForgotPasswordLinkTest(unittest.TestCase):
    def test_the_email_is_a_link_with_code_and_address_in_the_fragment(self):
        result = run(event())
        message = result["response"]["emailMessage"]
        self.assertIn(
            'href="https://app.example.se/aterstall-losenord#code={####}&amp;email=anna%40example.se"',
            message,
        )
        self.assertEqual(result["response"]["emailSubject"], "Välj ett nytt lösenord")
        self.assertIn("anna@example.se", message)

    def test_the_code_placeholder_appears_exactly_once(self):
        # Cognito puts the real code in place of the placeholder; a second
        # copy might be left as "{####}".
        message = run(event())["response"]["emailMessage"]
        self.assertEqual(message.count("{####}"), 1)

    def test_the_placeholder_cognito_sends_is_used(self):
        message = run(event(code="{%%%%}"))["response"]["emailMessage"]
        self.assertIn("#code={%%%%}&amp;", message)
        self.assertNotIn("{####}", message)

    def test_addresses_are_encoded_in_the_link_and_escaped_in_the_text(self):
        message = run(event(email="o'brien+bar&co@example.se"))["response"]["emailMessage"]
        self.assertIn("email=o%27brien%2Bbar%26co%40example.se", message)
        self.assertIn("o&#x27;brien+bar&amp;co@example.se", message)
        self.assertNotIn("o'brien", message)

    def test_a_trailing_slash_in_the_url_is_ignored(self):
        message = run(event(), url=RESET_URL + "/")["response"]["emailMessage"]
        self.assertIn("aterstall-losenord#code=", message)

    def test_without_an_address_the_link_carries_only_the_code(self):
        message = run(event(email=None))["response"]["emailMessage"]
        self.assertIn('href="https://app.example.se/aterstall-losenord#code={####}"', message)
        self.assertIn("ditt konto", message)

    def test_operators_get_english(self):
        result = run(event(), language="en", url="https://ops.example.se/reset-password")
        self.assertEqual(result["response"]["emailSubject"], "Choose a new Booqy Console password")
        self.assertIn('href="https://ops.example.se/reset-password#code={####}', result["response"]["emailMessage"])
        self.assertIn("authenticator code", result["response"]["emailMessage"])

    def test_every_body_is_html_cognito_accepts(self):
        for language in handler.TEXTS:
            message = run(event(), language=language)["response"]["emailMessage"]
            self.assertLess(len(message), 20000)
            self.assertEqual(message.count("{####}"), 1)

    def test_other_messages_are_left_to_the_pool_templates(self):
        for trigger in (
            "CustomMessage_AdminCreateUser",
            "CustomMessage_SignUp",
            "CustomMessage_ResendCode",
            "CustomMessage_UpdateUserAttribute",
            "CustomMessage_VerifyUserAttribute",
            "CustomMessage_Authentication",
        ):
            original = event(trigger=trigger)
            result = run(event(trigger=trigger))
            self.assertEqual(result, original, trigger)

    def test_without_a_reset_url_the_plain_code_email_is_kept(self):
        original = event()
        with mock.patch.dict(os.environ, {"LANGUAGE": "sv"}, clear=False):
            os.environ.pop("RESET_URL", None)
            result = handler.handler(event(), None)
        self.assertEqual(result, original)

    def test_an_unknown_language_falls_back_to_english(self):
        result = run(event(), language="de")
        self.assertEqual(result["response"]["emailSubject"], "Choose a new Booqy Console password")


if __name__ == "__main__":
    unittest.main()
