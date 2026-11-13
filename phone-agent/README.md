# phone-agent

AI phone booking agent (feature L). Off by default (entitlement `phoneAgent`, limit
`phoneAgentMinutesPerMonth` 0 in every plan); voice, telephony and the agent model are
simulators unless `var.voice_client`, `var.telephony_client`, `var.agent_model_client` say
`real` (the simulators are refused in prod at runtime).

- Decision record: `docs/adr/ADR-L-phone-agent.md` (decision 13: counter-offers); contract:
  `docs/build/CONTRACTS.md` (feature L, sections 0, 4, 5, 6.L, 9, 11, 13, 14, 17).
- Application: `functions/phone-agent`, `functions/phone-agent-call`, `functions/phone-agent-jobs`,
  `shared/features/phone_agent`.
- Routes: `network/api-gateway/phone-agent-routes.tf` (12 JWT routes, 4 operator routes). The
  provider webhooks L13/L14 and the agent turn endpoint (`POST /v1/chat/completions`) are served
  on the `phone-agent-call` Function URL (output `turn_endpoint_url`), because
  `feature-routes.tf` routes a feature to one integration only (reported, hotspot).
- ECR repositories: `phone_agent_ecr`, `phone_agent_call_ecr`, `phone_agent_jobs_ecr` (since the Run 0 addendum).

## Resources (all new)

| Resource | Name | Notes |
|---|---|---|
| DynamoDB table | `<prefix>phone-agent` | GSIs `byNumber`, `byReservation`; TTL; PITR; deletion protection in prod |
| S3 bucket | `<prefix>phone-agent-recordings-<account>` | private (public access blocked, owner-enforced), SSE-S3, lifecycle by object tag `retention` 7/30/90 days; written only with a tenant's recording opt-in (the copy step is not built yet) |
| Secrets | `${prefix}phone-agent/voice-provider`, `${prefix}phone-agent/telephony` | values by hand (provider accounts) |
| Secret | `${prefix}phone-agent/llm-endpoint-key` | `random_password`, the header the voice provider sends to the turn endpoint |
| Lambdas + `live` aliases | `phone-agent`, `phone-agent-call`, `phone-agent-jobs` | images from ECR, arm64 |
| Function URL | on `phone-agent-call:live` | auth NONE (the function checks the endpoint key or the provider signature), BUFFERED |
| Scheduler | `<prefix>phone-agent-sweep` (every 5 min), `<prefix>phone-agent-nightly` (03:00 Stockholm) | default group, own invoke role |
| Alarms | Errors per function; `Booqy/PhoneAgent` BilledMinutes per day > `daily_minutes_alarm` (600, [NEEDS YOUR OK]); ProviderErrors > 5 in 5 min; TurnLatencyMs p95 > 2500 ms for 15 min | metrics written as CloudWatch Embedded Metric Format log lines (no PutMetricData) |

## IAM (new roles; no existing role changed)

New row 2026-11-13, approved by the owner the same day: `phone-agent` / `EndpointKeyForVoiceAgent` (below).

| Role | Statement | Actions | Resource |
|---|---|---|---|
| all three | PhoneAgentTable | Get/Put/Update/DeleteItem, Query, BatchWriteItem | the new table and its indexes |
| all three | PublishPhoneAgentEvents | events:PutEvents | the bus, `events:source = booqy.phone-agent` |
| all three | ReadPlatformSettings | dynamodb:GetItem | **existing tenant table**, `LeadingKeys = PLATFORM#PHONE_AGENT` only |
| all three | ProviderSecrets | secretsmanager:GetSecretValue | the two new provider secrets |
| phone-agent | EndpointKeyForVoiceAgent (approved 2026-11-13) | secretsmanager:GetSecretValue | the endpoint key secret (the real voice client stores it once as an ElevenLabs workspace secret for the location agents' custom LLM) |
| phone-agent | WritePlatformSettings | dynamodb:PutItem | **existing tenant table**, `LeadingKeys = PLATFORM#PHONE_AGENT` only |
| phone-agent | AgentSystemUsers | dynamodb:PutItem, DeleteItem | **existing user table**, `LeadingKeys` like `USER#agent:*` only |
| phone-agent | InvokeReadTools | lambda:InvokeFunction | **existing** `tenant-site-config:live`, `get-availability:live`, `get-reservation:live`, `get-menu:live`, `list-layout-version:live` (the dry-run simulator) |
| phone-agent | Recordings, ListRecordingsForPurge | s3:GetObject, DeleteObject; s3:ListBucket (prefix `recordings/*`) | the new bucket |
| phone-agent-call | EndpointKey | secretsmanager:GetSecretValue | the new endpoint key secret |
| phone-agent-call | InvokeTools | lambda:InvokeFunction | **existing** `tenant-site-config`, `get-availability`, `create-pending-reservation`, `get-reservation`, `mark-arrived`, `get-menu`, `list-layout-version` (`:live` aliases only) |
| phone-agent-call | InvokeNotification | lambda:InvokeFunction | **existing** `notification:live` |
| phone-agent-call | FindOwners | dynamodb:Query | **existing user table**, its tenant index only |
| phone-agent, phone-agent-call | AgentModel (only when `phone_agent_model_id` is set) | bedrock:InvokeModelWithResponseStream | that model, its EU inference profile, the same model in EU regions |
| phone-agent-jobs | ScanPhoneAgentTable | dynamodb:Scan | the new table |
| all three | cloudwatch-logs | logs:CreateLogStream, PutLogEvents | own log group |
| (shared, via `wiring`) | tenant-context reads for all three; staff-check user read for phone-agent | attached by `config.tf` like every feature |
| scheduler role | InvokeJobs | lambda:InvokeFunction | `phone-agent-jobs:live` |

`cancel-reservation:live` is not invoked: the agent cancels through the staff status route on
`mark-arrived` (the guest route needs the manage-link token). The hook callers' invoke grants on
`phone-agent:live` exist since the Run 0 addendum (CONTRACTS.md 14 rows 11, 12, 16).

## Going live (real providers, ADR-L decision 14)

Set `voice_client`, `telephony_client`, `agent_model_client` to `real` per environment, plus
`phone_agent_model_id`, `phone_agent_voice_id` (and `elevenlabs_api_base` with EU residency).
Secrets (by hand, JSON): `${prefix}phone-agent/voice-provider` `{apiKey, webhookSecret,
initiationToken, callUrl}` (`callUrl` = output `turn_endpoint_url`), `${prefix}phone-agent/telephony`
`{username, password, webhookToken}`. ElevenLabs workspace: a post-call webhook to
`<callUrl>public/phone-agent/voice/webhook` with transcript events (its HMAC secret is
`webhookSecret`). The location agents, the SIP trunk numbers and the initiation webhook are created
by the API when a location is enabled.

## Unverified

- Everything against real providers (ElevenLabs, 46elks, Bedrock): adapters are built and unit
  tested with faked HTTP; shapes the provider docs did not confirm are marked `[VERIFY IN SANDBOX]`
  in `shared/voice_provider_real.py`. The Function URL's exposure is limited by the endpoint key and
  the provider signatures only (no API Gateway throttle on L13/L14).
- Reserved concurrency for `phone-agent-call` is a per-environment variable
  (`phone_agent_call_reserved_concurrency`, default -1 = unreserved): dev reserves 2, prod is
  undecided (owner, before L goes live). Provisioned concurrency (ADR-L latency budget) is not set:
  owner decision on cost.
