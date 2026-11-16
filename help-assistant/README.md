# help-assistant

In-app help assistant: "Fråga Booqy" in Booqy Admin (Swedish) and "Ask Booqy"
in Booqy Console (English). Answers "how do I ..." questions step by step
from the app's own help corpus, with buttons that open the right page.

- Application: `functions/help-assistant`, `shared/help_assistant.py`.
- Knowledge: each app builds its corpus from its own code at build time
  (admin-front-end `scripts/help-corpus.mjs`, booqy-console
  `web/scripts/help-corpus.mjs`) and deploys it as
  `help-corpus.<hash>.json`; the app's `index.html` names that file in
  `<meta name="booqy-help-corpus">`. The Lambda reads `HELP_APP_URL_ADMIN` /
  `HELP_APP_URL_CONSOLE` (`app_urls`, https), follows the meta tag to the
  corpus (cached 10 minutes) and falls back to the bundled copy
  `shared/help_corpus_<app>.json` (refreshed with `npm run help-kb:sync` in
  each app; `-- --check` fails when the copy is stale).
- Routes (`network/api-gateway`):
  - Admin, tenant JWT (owners and staff): `GET /tenant/help-assistant`
    (status), `POST /tenant/help-assistant/answers`
    (`help-assistant-routes.tf`).
  - Console, operator JWT (`platform` authorizer; the Lambda also requires
    the `platform_admin` group): `GET /platform/help-assistant`,
    `POST /platform/help-assistant/answers`
    (`help-assistant-operator-routes.tf`).
- Off unless `help_assistant_enabled = true` (on in dev.tfvars, not set in
  prod). Kill switch without a deploy: put `{PK: "PLATFORM#HELP_ASSISTANT",
  SK: "SETTINGS", enabled: false}` on the tenant table (read every 60 s).
  Then a question gets 403 `{"error": "help_assistant_off"}` and the apps
  close the assistant instead of answering from their local corpus.
- Model: Bedrock is only called with `bedrock_client = "real"` and a model id
  (`help_assistant_bedrock_client` / `help_assistant_model_id`, else the
  shared `bedrock_client` / `bedrock_model_id`). Dev uses the EU inference
  profile `eu.anthropic.claude-haiku-5-5`, so data stays in EU regions. Past
  a cap, or on any model error, the answer is composed from the best
  matching corpus texts (no model call, no cost).
- Limits: 6 questions a minute and 60 an hour per user; Bedrock answers
  capped by `help_assistant_monthly_answers` (default 300 per tenant, with
  all operators sharing one "platform" budget, and 10 000 for the whole
  platform, per 30-day window). Counters are hashed keys with TTL in the
  existing request-guard table.
- Errors: server error bodies carry the Lambda `requestId`, so a "Booqys
  fel" report can name the request.
- Privacy: questions and answers are never stored or logged (the log line
  has the outcome only); the conversation lives in the app tab's memory.
- Resources: Lambda `help-assistant` (+ `live` alias, log group 30 days,
  Errors alarm), ECR repository `help-assistant` (config.tf).
- IAM, role `help-assistant`: `dynamodb:UpdateItem` on the request-guard
  table; `bedrock:InvokeModel` on the model id's foundation model and
  inference profile ARNs, and for an EU inference profile (`eu.<model>`)
  the underlying model in EU regions
  (`arn:aws:bedrock:eu-*::foundation-model/<model>`); only when a model id
  is set; logs to its own log group. Attached to the shared tenant-context
  read policy (tenant table GetItem/Query, location reads) via
  `tenant_aware_role_names`.
