# meta-ads

Meta ads (feature A, `metaAds`): owners connect their Meta business assets
and run Facebook/Instagram ads for bookings, orders and catering.

- Decision record: `docs/adr/ADR-A-meta-ads.md`; contract: `docs/build/CONTRACTS.md`
  (feature A, sections 0, 4, 5, 6.A, 9, 11 and 12).
- Resources: table `<prefix>meta-ads` (+ sparse GSI `byConnected`), Lambdas
  `meta-ads` (API, platform hook, purge) and `meta-ads-jobs` (workflow tasks,
  insights, sweep), Standard state machine `<prefix>meta-ads-publish`
  (`definitions/publish.asl.json`, JSONata, retries on Meta/Lambda errors,
  Catch -> MarkFailed), schedules (insights 04:00 Europe/Stockholm, kill-switch
  sweep every 15 minutes, which also starts publishes stuck in `publishing`
  without an executionArn for 10 minutes or marks them `start_failed`), secret `${prefix}meta-ads/app` (value set by hand),
  Errors, failed-execution and platform spend alarms.
- Clients: `META_CLIENT` / `BEDROCK_CLIENT` from the root `meta_client` /
  `bedrock_client` (default simulator; the simulator is refused in prod at
  runtime). Bedrock access is granted only when `bedrock_model_id` is set.
- IAM (new roles only): own table + GSI; Secrets Manager create/put/get/
  delete/tag on `booqy/<env>/meta-ads/*` and get on the app secret;
  `states:StartExecution` on the state machine (API and, for the sweep's
  restart of stranded publishes, the jobs function); GetItem on the menu table;
  Query on the marketing table (STATS, read-only); GetItem/PutItem on the
  tenant table limited to the `PLATFORM#META_ADS` partition (kill switch);
  `s3:GetObject` on `menu-images/*`; Query on the user table's tenant index
  (owner emails for the 80 % mail); invoke `notification:live` and
  `meta-ads-jobs:live`; `events:PutEvents` with `events:source =
  booqy.meta-ads`; `cloudwatch:PutMetricData` limited to `Booqy/MetaAds`;
  `bedrock:InvokeModel` on one model/profile when configured.
- Outputs `table_name`, `table_arn`, `tenant_secret_prefix` for feature G.
