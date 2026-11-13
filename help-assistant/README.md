# help-assistant

In-app help chatbot in Booqy Admin: "how do I ..." questions answered step by
step from a curated help knowledge base, with buttons that open the right page.

- Application: `functions/help-assistant`, `shared/help_assistant.py`, knowledge
  base `shared/help_kb.json` (synced from admin-front-end
  `src/features/help/helpKb.json` with `npm run help-kb:sync`).
- Routes (JWT, owners and staff): `GET /tenant/help-assistant` (status),
  `POST /tenant/help-assistant/answers`.
- Off unless `help_assistant_enabled = true` (on in dev.tfvars, off in prod).
  Kill switch without a deploy: put `{PK: "PLATFORM#HELP_ASSISTANT", SK:
  "SETTINGS", enabled: false}` on the tenant table (read every 60 s).
- Bedrock is only called with `bedrock_client = "real"` and a
  `bedrock_model_id`; otherwise, past a cap or on any model error, the answer
  is the best matching help text (no model call, no cost).
- Limits: 6 questions a minute and 60 an hour per user; Bedrock answers capped
  by `help_assistant_monthly_answers` (default 300 per tenant, 10 000 for the
  platform, per 30-day window). Counters are hashed keys with TTL in the
  existing request-guard table.
- Privacy: questions and answers are never stored or logged (the log line has
  the outcome only); the conversation lives in the admin tab's memory.
- Resources: Lambda `help-assistant` (+ `live` alias, log group 30 days,
  Errors alarm), ECR repository `help-assistant` (config.tf).
- IAM (**owner to approve**). New role `help-assistant`:
  `dynamodb:UpdateItem` on the request-guard table; `bedrock:InvokeModel` on
  the `bedrock_model_id` foundation model and inference profile ARNs, and
  for an EU inference profile (`eu.<model>`) the underlying model in EU
  regions (`arn:aws:bedrock:eu-*::foundation-model/<model>`); only when a
  model id is set; logs to its own log group. Attached to the shared
  tenant-context read policy (tenant table GetItem/Query, location reads) via
  `tenant_aware_role_names`.
