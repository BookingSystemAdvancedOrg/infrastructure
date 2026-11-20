# site-translate

Site languages: `POST /translate` translates Swedish site text to English,
Spanish, Arabic and Persian with Amazon Translate. The restaurant sites call
it as `/api/translate` (their CloudFront, through the AWS WAF); the function
finds the restaurant from the trusted viewer host and rejects unknown hosts.

- Resources: table `<prefix>site-translations` (PAY_PER_REQUEST, SSE, TTL on
  `ttl`, no PITR, no deletion protection: a cache keyed by a hash of the
  protected source, shared by all sites), Lambda `site-translate` (arm64,
  512 MB, 28 s, reserved concurrency 10, alias `live`), log group (30 days),
  alarms: Errors, `TranslatedChars` (Booqy/SiteTranslate, no dimensions) over
  80% of the daily share of the 30-day platform budget on 2 of 3 days, and
  `BudgetLimited` >= 1.
- Limits (Lambda env from `site_translate_*` variables, set in the tfvars):
  `SITE_TRANSLATE_IP_REQUESTS_PER_5MIN`, `SITE_TRANSLATE_IP_CHARS_PER_HOUR`,
  `SITE_TRANSLATE_TENANT_CHARS_PER_30D`, `SITE_TRANSLATE_GLOBAL_CHARS_PER_30D`.
  The counters live in the existing request-guard table.
- Other env: `ENVIRONMENT`, `TRANSLATION_TABLE_NAME`, `TENANT_TABLE_NAME`,
  `REQUEST_GUARD_TABLE_NAME`, `SITE_WAF_SECRET`, `CLOUDFRONT_EDGE_SECRET`.
- IAM (**owner to approve**). New role `<prefix>site-translate-role` only:
  - `translate:TranslateText` on `*` (no resource-level permission without terminology)
  - `dynamodb:BatchGetItem, BatchWriteItem, GetItem, PutItem, UpdateItem` on the cache table
  - `dynamodb:UpdateItem` on the request-guard table (counters)
  - `dynamodb:GetItem` on the tenant table (resolve host to restaurant)
  - `logs:CreateLogStream, PutLogEvents` on its log group
  No existing role, OIDC or deploy role, CloudFront, WAF or CORS change.
- Route: `network/api-gateway/site-translate-routes.tf`
  (`POST /translate`, public, public throttle 50 rps burst 100). API Gateway
  gets the usual invoke permission through `feature_api_integrations`.
- ECR repository `site-translate` is created in `config.tf`; the application
  CI pushes the image, then the release script points the alias at it.
- Application: `functions/site-translate`, `shared/site_translate.py`.
