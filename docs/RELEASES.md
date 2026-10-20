# Releases: rollout, rollback, re-run, alarms

One page for the day something goes wrong. Nothing in a release needs a
manual approval: merging `dev` to `main` deploys production, the guards
below catch a bad release, and every rollback is one workflow run.

## Rollout order

| # | Repo | Pipeline does | Guard |
|---|---|---|---|
| 1 | `infrastructure` | PR: fmt, validate, plan **posted as a PR comment**. Merge: apply, then a CodeDeploy release of every Lambda whose configuration changed, then the smoke test | Plan comment, Lambda alarms, smoke test |
| 2 | `application` | Tests, image per function, blue/green release of every function (production: 10% for 5 minutes), smoke test | Lambda alarms roll back on their own, smoke test |
| 3 | `admin-front-end`, `customer-front-end`, `booqy-console` | Lint, tests, build, `s3 sync`, invalidation (console: also the API Lambda release), smoke test | Smoke test, CloudFront alarms, bucket versioning |

Same order from `dev` to `main`. Wait for each pipeline to finish before
merging the next; a failed smoke test means stop and roll back that layer.

**Smoke test** (`ci/smoke-test.sh`, a copy in each repo's `scripts/`):
`GET /site-config` answers (200 for `smoke_test_host`, 404 for an unknown
host while no permanent test restaurant exists), and the customer site,
admin app and console each serve their app shell and script bundle. Retries
for 90 seconds (invalidation), then fails the job and emails the alerts
topic. Success sends nothing. Values live in each repo's
`.github/config/project.env` (`SMOKE_*`) and in `smoke_test` (Terraform output).

## Rolling back

### Lambda (application, booqy-console API)

- **During the canary** nothing to do: an error-rate or throttle alarm on
  the function's live alias moves traffic back and emails "ROLLED BACK".
- **After the release:** `Actions -> Redeploy a commit` in the repo, branch
  `main` (production) or `dev`, the SHA of the last green run. It rebuilds
  that commit and releases every function through the same canary.
- **One function, no rebuild:** `lambda-release.sh --to-version N`
  (booqy-console: `Actions -> Rollback`, which finds N itself). N is in the
  last successful CodeDeploy deployment's description, `v<from> -> v<to>`.

### Frontends (admin app, customer site, console web)

`Actions -> Redeploy a commit`, branch `main` or `dev`, environment, the SHA
of the last green run. The commit must be on that branch; the run builds,
deploys and smoke tests it like a normal push. The asset buckets are
versioned: everything a deploy overwrote or deleted stays for 30 days as
noncurrent versions, so a redeploy is a no-risk rollback (and, as a last
resort, `aws s3api list-object-versions` + `copy-object` with the
`--copy-source ...?versionId=` of `index.html` and its assets restores a
build by hand).

### Terraform

Never apply by hand. `git revert <merge commit>` on `dev`, open the PR to
`main`, read the plan comment, merge. A revert that destroys data (a
table, a bucket with content) is not a rollback, it is a new change: read
the plan. State is in S3 with a lock file; a run that died mid-apply leaves
no lock behind (`use_lockfile`), re-run it.

## Re-running a release

- **Failed run:** `Actions -> the run -> Re-run failed jobs`. Releases of
  one environment never overlap (concurrency groups); `lambda-release.sh`
  waits for a deployment that is still shifting and skips functions already
  on the new version, so a re-run is safe at any point.
- **Infrastructure "Release Lambda configuration changes" failed:** re-run
  the job; `$LATEST` already has the configuration, the re-run only moves
  the alias.
- **Nothing to re-run but the environment is wrong:** redeploy the last
  good commit (above) rather than pushing a fix under pressure.

## Where alarms go

Two SNS topics per environment, both emailing `alert_emails`
(`dev.tfvars` / `prod.tfvars`); every address confirms each topic once.

| Topic | Region | Fires on |
|---|---|---|
| `platform-alerts` (`dev-platform-alerts`) | eu-north-1 | Lambda release rollbacks and failed releases, failed smoke tests, DLQ stuck and replay errors, SES bounce/complaint rate, SMS spend, API 5xx rate (> 5%, at least 5 errors in 5 min), API p99 latency (> 5 s, 10 of 15 min), uptime check (customer site, admin app, `/site-config` failing 2 of 3 runs), the uptime check Lambda erroring. OK emails when a metric alarm recovers |
| `platform-alerts-us-east-1` | us-east-1 | CloudFront 5xx rate (> 5% with at least 20 requests, 10 min) on the admin, customer and tenant-sites distributions. CloudFront metrics only exist in us-east-1 and an alarm can only notify a topic in its own region |

Where to look when one arrives: CloudWatch Alarms in eu-north-1 (CloudFront:
us-east-1), CodeDeploy deployments (`lambda-releases` app), the
`uptime-check` Lambda's log (status and body of each failed request), the
GitHub Actions run linked in the email. Alarms in production roll Lambda
releases back; in dev the same alarms only email (no canary).
