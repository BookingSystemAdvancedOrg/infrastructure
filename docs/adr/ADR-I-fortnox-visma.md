# ADR-I: Direct posting to Fortnox and Visma

**Status:** Proposed
**Date:** 2026-11-01
**Deciders:** Owner (product), accountant reviewer, orchestrator
**Run:** built in Run 3
**Kassa removed 2026-11-14:** Booqy is online only; Kassa, the till, its routes, plan feature and fiskaly access are gone (the two kassa tables are kept for 7 years, `infrastructure/kassa.tf`). Kassa parts below are history.

## Context

Bokföring (BR-REST-089) builds one balanced verifikation per location and
business day (`shared/accounting.py` `build_entry` / `build_company`, plus a
company Stripe entry when locations share a Stripe account) and exports SIE 4
or CSV through `AccountingTarget` in `shared/accounting_export.py`, whose
docstring already reserves Fortnox and Visma as targets that "post each entry
as a voucher, return the voucher ids in Delivery.references". Entries are
rebuilt from source records on every export; nothing is stored. The account
mapping is on the location row (`accounting`). The legal entity is the
tenant. Owners use the owner-only `bokforing` tab in Inställningar.

## Decision

1. **One connection per tenant** (one company, one org number), provider
   `fortnox` or `visma`, never both at once. OAuth 2.0 authorization code
   flow started by the owner; Booqy never sees the owner's password.
2. **Tokens in Secrets Manager** per tenant:
   `booqy/<env>/accounting-sync/<tenantId>` holding `{provider,
   accessToken, refreshToken, expiresAt, companyId}`. Booqy's own app
   credentials per provider are Terraform-created platform secrets
   `${prefix}accounting-sync/fortnox-app` and `.../visma-app`
   (`ignore_changes`, set by hand).
3. **Two new targets** implementing `AccountingTarget`: `FortnoxTarget`,
   `VismaTarget` (`key = "fortnox" | "visma"`). Each gets an `Export` with
   **exactly one entry** and returns `Delivery(target, references=(voucherId,))`.
   They call a provider port following `shared/control_system.py`:
   `FortnoxClient` / `SimulatedFortnoxClient` chosen by `FORTNOX_CLIENT`,
   `VismaClient` / `SimulatedVismaClient` by `VISMA_CLIENT`, from validated
   Terraform variables `fortnox_client` and `visma_client`
   (`simulator` | `real`); simulator refused when `ENVIRONMENT=prod`.
   SIE/CSV stay unchanged and remain the fallback.
4. **Posting unit and key.** One unit = one entry: a location day, or the
   company Stripe entry for a day. Key
   `<tenantId>#<scope>#<yyyy-mm-dd>` where scope is the `locationId` or
   `company-<companyKey>`. The key is written into the voucher's description
   text so it can be found again in the provider.
5. **Queue.** An SQS FIFO queue `<prefix>accounting-sync.fifo` with
   `MessageGroupId = tenantId` (serialises one tenant, so a rotating refresh
   token is never used twice at once; tenants run in parallel) and
   `MessageDeduplicationId = <key>#<entryHash[:16]>`. `maxReceiveCount` 5
   with backoff, then the FIFO DLQ `<prefix>accounting-sync-dlq.fifo`.
6. **Exactly once per key.** Worker: conditional update of the `DAY#` item
   from `pending | failed` to `posting` with a lease; on success store the
   voucher reference and `entryHash`, status `posted`. A unit already
   `posted` is skipped. On an unknown outcome (timeout after send) the worker
   first searches the provider for a voucher with the key in its text on that
   date and series; found -> record it, not found -> post. Never blind-retry.
7. **When to post.** A nightly schedule (04:00 Europe/Stockholm) enqueues
   days `D <= today - lagDays` (default 2, so Stripe fees and payouts are
   in) from `startDay` onward, for tenants with `autoPost`. The owner can
   also post a range by hand. **`startDay` is required on connect** so days
   already imported by SIE are never posted twice.
8. **No silent re-posting.** If an entry rebuilt later has a different
   `entryHash` than the posted one, the day becomes `changed_after_posting`
   and is shown to the owner. BFL forbids editing a posted verifikation;
   correction vouchers are an open question, not v1.
9. **Non-retryable errors** (missing account in the chart, closed or missing
   financial year, locked period, revoked consent) set `needs_attention`
   with a Swedish reason and are not retried; connection `needs_reauth` on
   401 after refresh fails (shared enum `ConnectionStatus`).

## Data model

Table `<prefix>accounting-sync` (PAY_PER_REQUEST, PITR, deletion protection
in prod, TTL `ttl`).

| PK | SK | Item |
|---|---|---|
| `TENANT#<t>` | `CONNECTION` | `provider`, `status` (`connected` \| `needs_reauth` \| `disconnected`), `companyName`, `providerOrgNumber`, `connectedAt`, `connectedBy`, `startDay`, `autoPost`, `lagDays` (1-7), `version` |
| `TENANT#<t>` | `OAUTH#<nonce>` | `provider`, `sub`, `ttl` = now + 10 min (single use, deleted on callback) |
| `LOCATION#<l>` (SK `DAY#<yyyy-mm-dd>`) or `TENANT#<t>` (SK `COMPANY#<companyKey>#DAY#<yyyy-mm-dd>`) | see PK | `tenantId`, `key`, `status` (`pending` \| `posting` \| `posted` \| `failed` \| `needs_attention` \| `changed_after_posting`), `provider`, `entryHash`, `voucher` `{series, number, id}`, `attempts`, `leaseUntil?`, `lastError?` `{code, text}`, `postedAt?`, `version`, `ttl` = end of 7th year after the day |

The company scope lives in the tenant partition, so all PKs are reached only
after the tenant/location check and purge needs no extra key list. Status list: Query one PK with an SK range. No GSI.
The provider's org number must match the tenant's `orgNumber`; a mismatch
refuses the connection (409 `org_number_mismatch`).

## API routes

All JWT routes are **owner only** (the bokforing tab is owner-only).

| # | Method | Path | Auth | Request -> response |
|---|---|---|---|---|
| 1 | GET | `/tenant/accounting-sync` | JWT owner | -> `{connection?, locations[{locationId, posted, failed, needsAttention, lastPostedDay}]}` |
| 2 | POST | `/tenant/accounting-sync/connect` | JWT owner | `{provider, startDay}` -> `{authorizeUrl}` (state = signed nonce) |
| 3 | PUT | `/tenant/accounting-sync` | JWT owner | `{autoPost?, lagDays?, startDay?, version}` -> connection |
| 4 | DELETE | `/tenant/accounting-sync` | JWT owner | -> 204; revokes at the provider, deletes the secret (7-day recovery) |
| 5 | GET | `/locations/{locationId}/accounting-sync/days?from&to` | JWT owner | -> `{days[]}` (max 93 days) |
| 6 | POST | `/locations/{locationId}/accounting-sync/post` | JWT owner | `{from, to}` -> 202 `{queued, skipped}` |
| 7 | GET | `/public/accounting-sync/callback?code&state` | none (state-checked) | -> 302 to admin `/installningar?flik=bokforing&koppling=ok\|fel` |

Errors: 400 `invalid_provider`, `invalid_range`, `start_day_required`,
`range_before_start_day`; 403 `feature_not_in_plan`, `owner_only`; 404 foreign
location, unknown or reused state (callback), feature off (callback); 409
`already_connected`, `not_connected`, `org_number_mismatch`, `changed_retry`.

Idempotency: connect while a connection exists returns 409; callback with a
used nonce returns the same redirect as success if the connection is
`connected`, else 404; route 6 enqueues only units not `posted` and relies on
FIFO deduplication; route 4 twice -> 204.

## Events

Bus `<prefix>booqy-events`, source `booqy.accounting-sync`. Detail:
`tenantId`, `occurredAt`, `version: 1`.

| detail-type | extra detail |
|---|---|
| `AccountingSync.Connected` | `provider` |
| `AccountingSync.Disconnected` | `provider`, `reason` (`owner` \| `revoked`) |
| `AccountingSync.DayPosted` | `scope`, `day`, `provider`, `voucherId` |
| `AccountingSync.PostingFailed` | `scope`, `day`, `code`, `retryable` |

`PostingFailed` with `retryable: false` drives the Bokföring status and an
"Att göra" line later; no other consumer.

## Terraform modules

- `infrastructure/accounting-sync/`: table, FIFO queue + FIFO DLQ (14 days,
  SSE, `DenyInsecureTransport`), Lambda `accounting-sync` (API routes,
  callback, SQS worker via event source mapping with
  `ReportBatchItemFailures`, nightly enqueue target), nightly
  `aws_scheduler_schedule` (`flexible_time_window OFF`, retry policy),
  platform app secrets, alarms (Errors, DLQ depth > 0).
- Root `accounting-sync.tf` passes `var.fortnox_client` and
  `var.visma_client` (declared by Run 0 in `external-clients.tf`).
- Routes `network/api-gateway/accounting-sync-routes.tf`.
- **IAM (new role, call out):** read on reservation, order, kassa journal,
  catering, location, tenant tables the same as the `accounting` role;
  `secretsmanager:CreateSecret`, `PutSecretValue`, `GetSecretValue`,
  `DeleteSecret` limited to `booqy/<env>/accounting-sync/*`;
  `GetSecretValue` on the two app secrets; SQS send/receive/delete on its
  queues; `events:PutEvents` on the bus.
- `dlq-replay` handles standard queues today: either extend it to FIFO or
  replay this DLQ from the Bokföring status (route 6). Decision: route 6;
  `dlq-replay` is not changed.
- Wiring through the module's `wiring` output (ECR repo by Run 0); purge is
  the `tenant.purge` hook (rows and the tenant secret). Building entries
  goes through `shared/accounting.build_company`, which includes the
  `accounting.events` hook, so this role also needs invoke on
  `gift-cards:live`.

## Entitlement name

`accountingSync`. Off -> 403 on JWT routes, 404 on the callback; the worker
and the nightly job skip tenants without it (units stay `pending`).

## Plan availability (target)

growth. Starter keeps SIE/CSV export. Run 0 ships `false` in every plan.

## UI placement

- Admin, `/installningar`, owner-only `bokforing` tab: new card
  "Direktbokföring" above `BokforingCard`: "Koppla Fortnox" / "Koppla Visma",
  required "Bokför från och med" date, "Bokför automatiskt" toggle, per
  location a day list with status ("Bokförd", "Väntar", "Behöver åtgärd",
  "Ändrad efter bokföring") and the voucher number, "Bokför nu" for a range,
  "Koppla från". SIE/CSV export stays below unchanged.
- Console: only the generic feature checkbox.
- Storage registry: no new keys (OAuth state is server-side).

## External dependencies

- Fortnox API and Visma eEkonomi API: **mocked** in Runs 1-3.
- **Approval needed:** a Fortnox integration/partner app and a Visma
  developer app (client ids, redirect URIs per environment, possibly a
  partner agreement and review). Human action; nothing in code.
- Check each provider's voucher idempotency options; if one offers a real
  idempotency key, use it instead of the search in Decision 6.

## Privacy and GDPR

- Verifikationer are aggregates per day: no guest data leaves Booqy. The
  owner's `sub` is stored as `connectedBy`.
- Fortnox/Visma are the restaurant's own systems; the restaurant is
  controller, Booqy processor; the DPA lists the transfer when enabled.
- Tokens never logged or returned; error texts from providers are stored
  only after removing anything that looks like a token.
- Retention: `DAY#` rows 7 years (part of the posting trail); OAuth nonces
  10 minutes. Tenant-purge deletes the table rows and the secret
  (räkenskapsinformation itself lives in the tenant's provider and in the
  source records Booqy already keeps).

## Swedish legal notes (human check)

- BFL 5 kap. 5 § and 7 §: a posted verifikation must not be changed;
  corrections are new vouchers referring to the original. Confirm v1's
  "flag, do not repost" is acceptable.
- BFL 5 kap. 11 § (systemdokumentation och behandlingshistorik): document
  the posting flow and keep the `DAY#` log; confirm 7 years (BFL 7 kap. 2 §).
- Who is responsible when Booqy posts on the restaurant's behalf (consent
  text on connect).
- Accountant review of the series and numbering used in the provider versus
  Booqy's `entry_number`.

## Test plan

Two-tenant fixtures, `mock_aws()`, simulated clients. Each route: happy path,
validation error, wrong role, foreign tenant 404, entitlement off, idempotent
retry.

| # | Validation | Wrong role (staff) | Foreign 404 | Off | Retry |
|---|---|---|---|---|---|
| 1 | n/a | 403 | only A's locations | 403 | n/a |
| 2 | bad provider; no startDay | 403 | n/a (tenant from JWT) | 403 | second connect 409 |
| 3 | lagDays 9 | 403 | n/a | 403 | stale version 409 |
| 4 | n/a | 403 | n/a | 403 | second delete 204 |
| 5 | 94-day range | 403 | LOC_B 404 | 403 | n/a |
| 6 | range before startDay | 403 | LOC_B 404 | 403 | second call queues nothing new |
| 7 | missing code | n/a | state signed for B used in A's session: 404; reused nonce | 404 | second callback same redirect |

Worker and job: same unit delivered twice -> one voucher; crash after the
provider accepted -> search finds it, no duplicate; 5 failures -> DLQ and
`failed`; non-retryable error -> `needs_attention`, no retry; refresh token
rotated once per tenant even with 30 queued units; nightly job run twice ->
same queue content (dedup); resumable after timeout (re-invokes, skips
`posted`); changed entry -> `changed_after_posting`; isolation: a message for
tenant A can only load A's secret and A's locations; SIE export output
unchanged (existing tests untouched). UI: light and dark, mobile, tablet,
desktop.

## Alternatives considered

- **Post the whole period as one batch**: one failure blocks all days and
  idempotency gets coarse. Rejected.
- **Standard SQS + DynamoDB lease per tenant** for token refresh: works, but
  FIFO groups give the same serialisation for free.
- **Step Functions per posting**: more moving parts for a two-call job.
- **Third-party aggregator** (one API for many ERPs): fees, another data
  processor, and still per-provider quirks.

## Open questions

1. Correction vouchers for `changed_after_posting` days (automatic
   difference voucher or manual)?
2. One provider per tenant or per location (franchise with several org
   numbers)? v1: per tenant, matching the legal entity on the tenant row.
3. Should a tenant switching from SIE be offered a dry run that lists what
   would be posted?
