"""Cognito custom message trigger - the "forgot password" email as a link.

One function per user pool (config.tf):

    tenant pool    Swedish, a link to the restaurant admin app's
                   /aterstall-losenord page
    operator pool  English, a link to Booqy Console's /reset-password page

For ForgotPassword Cognito emails a 6-digit code. This trigger turns the
email into a link that carries the code and the address in the URL
fragment:

    <RESET_URL>#code=123456&email=anna%40example.se

A fragment never reaches a server (CloudFront, logs, Referer headers), and
the page removes it from the address bar once read. The page then only asks
for the new password and sends email + code + password to Cognito
(ConfirmForgotPassword). The code works once and for one hour; a newer
request replaces it.

Every other message (invitations, verification codes) is left to the pool's
templates: the event comes back unchanged.

Cognito only accepts a custom email from a pool that sends through SES
(EmailSendingAccount DEVELOPER) - storage/cognito* attach this trigger only
then. Without RESET_URL the email falls back to the plain code, which the
apps also accept.

Infra-owned and deployed as a zip by Terraform, like pre-token-generation:
the trigger runs inside the ForgotPassword call, so a failing or placeholder
function would break every password reset. No I/O, no dependencies.
"""

import html
import os
from urllib.parse import quote

TEXTS = {
    "sv": {
        "account": "ditt konto",
        "subject": "Välj ett nytt lösenord",
        "body": (
            "Hej!<br><br>"
            "Vi har fått en begäran om ett nytt lösenord för {email} i restaurangens "
            "adminpanel.<br><br>"
            '<a href="{link}"><b>Välj ett nytt lösenord</b></a><br><br>'
            "Länken fungerar en gång och i en timme. Har du inte bett om ett nytt "
            "lösenord kan du bortse från det här mejlet - ditt lösenord ändras inte."
        ),
    },
    "en": {
        "account": "your account",
        "subject": "Choose a new Booqy Console password",
        "body": (
            "Hi,<br><br>"
            "We received a request for a new password for {email} in Booqy Console.<br><br>"
            '<a href="{link}"><b>Choose a new password</b></a><br><br>'
            "The link works once and for one hour. You still sign in with your "
            "authenticator code afterwards. If you didn't ask for a new password, "
            "ignore this email - your password stays the same."
        ),
    },
}


def reset_link(base_url, code_parameter, email):
    """The page URL with the code placeholder and the address in the fragment."""
    fragment = f"code={code_parameter}"
    if email:
        fragment += "&email=" + quote(email, safe="")
    return f"{base_url}#{fragment}"


def handler(event, context):
    if event.get("triggerSource") != "CustomMessage_ForgotPassword":
        return event

    base_url = os.environ.get("RESET_URL", "").strip().rstrip("/")
    if not base_url:
        print("RESET_URL is not set - the reset email shows the plain code")
        return event

    texts = TEXTS.get(os.environ.get("LANGUAGE", "en"), TEXTS["en"])
    request = event.get("request") or {}
    # Cognito replaces this placeholder with the code; it must appear in the
    # message exactly once (inside the link).
    code_parameter = request.get("codeParameter") or "{####}"
    email = ((request.get("userAttributes") or {}).get("email") or "").strip()

    link = reset_link(base_url, code_parameter, email)
    response = event.setdefault("response", {})
    response["emailSubject"] = texts["subject"]
    response["emailMessage"] = texts["body"].format(
        email=html.escape(email or texts["account"]),
        link=html.escape(link, quote=True),
    )
    return event
