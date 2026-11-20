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
  Glossary answers and cache hits never count on a budget. Dev: 3,000,000
  per restaurant and 5,000,000 for the platform per 30 days (dev tests switch
  whole sites through every language). Prod: 500,000 per restaurant (about
  7.50 USD) and 5,000,000 for the platform (about 75 USD). To raise a cap,
  change `site_translate_tenant_chars_per_30d` (or the global one) in
  `prod.tfvars`, push to dev, merge to main: CI applies it and releases the
  function's new configuration. The `BudgetLimited` alarm says when a cap binds.
- Custom terminology `<prefix>site-translate-terms` from `terminology.csv`
  (first column Swedish, then en, es, ar, fa; one term per row, matched
  without regard to case, so no rows that differ only in case): restaurant
  words that Amazon Translate got wrong inside whole sentences (bord was a
  spreadsheet table, platser were web sites). Imported by CI on apply with
  `aws translate import-terminology` (`terraform_data.terminology`, no
  Terraform resource exists), again only when the CSV changes; the function
  gets the name and a hash of the CSV (`SITE_TRANSLATE_TERMINOLOGY`,
  `SITE_TRANSLATE_TERMINOLOGY_HASH`) and passes it as `TerminologyNames`. The
  hash is part of the cache key, so an edited CSV is used for every text at
  once. Add a word: one row, all five columns, push to dev. Not deleted on
  destroy (it costs nothing; `aws translate delete-terminology` by hand).
- Other env: `ENVIRONMENT`, `TRANSLATION_TABLE_NAME`, `TENANT_TABLE_NAME`,
  `REQUEST_GUARD_TABLE_NAME`, `SITE_WAF_SECRET`, `CLOUDFRONT_EDGE_SECRET`.
- IAM (**owner to approve**). New role `<prefix>site-translate-role` only:
  - `translate:TranslateText` on `*` (covers using the terminology: TranslateText
    needs no other action for it; `ImportTerminology` is the CI role's, which has
    AdministratorAccess in dev and prod)
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
