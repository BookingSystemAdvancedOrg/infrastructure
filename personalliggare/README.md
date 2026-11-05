# personalliggare

Personalliggare, the electronic staff ledger (feature H). **Needs legal review**
before the entitlement `personalliggare` is turned on for any tenant (false in
every plan).

- Decision record: `docs/adr/ADR-H-personalliggare.md`; contract: `docs/build/CONTRACTS.md`
  (feature H, sections 0, 4, 5, 6.H, 9 and 12).
- Built in Run 2 (batch 2). Application: `functions/personalliggare`,
  `shared/features/personalliggare`.
- Routes: `network/api-gateway/personalliggare-routes.tf` (8 JWT routes, operator route H9
  forwarded by Booqy Console's platform-tenants).
- ECR repository: `module "personalliggare_ecr"` in `config.tf` (since Run 0).
- Test: `tests/ledger.tftest.hcl` (mocked AWS provider) asserts the append-only policy,
  the role's ledger actions and deletion protection.

## Resources (all new)

| Resource | Name | Notes |
|---|---|---|
| DynamoDB table | `<prefix>personalliggare` | state: persons, user pointers, HEAD, presence, REQ markers (TTL 7 d); PITR; deletion protection in prod; purged by the `tenant.purge` hook |
| DynamoDB table | `<prefix>personalliggare-ledger` | append-only ledger, GSI `byDay`, TTL `ttl` (end of the 2nd calendar year, legal to confirm), PITR, deletion protection in **every** environment; never purged |
| DynamoDB resource policy | on the ledger | `Deny` UpdateItem, DeleteItem, BatchWriteItem, PartiQLUpdate, PartiQLDelete for `Principal: *` (same shape as kassa's journal) |
| Lambda + alias `live` | `<prefix>personalliggare` | image from ECR, arm64, 28 s |
| IAM role | `<prefix>personalliggare-role` | see below |
| Log group, Errors alarm | | alarm to the existing alert topic |

## IAM (new role `<prefix>personalliggare-role`; no existing role changed)

| Sid | Actions | Resource |
|---|---|---|
| StateTable | Get/Put/Update/DeleteItem, Query, BatchWriteItem | the new state table |
| LedgerAppendAndRead | PutItem, GetItem, Query | the new ledger table and its `byDay` index |
| PublishLedgerEvents | events:PutEvents | the `booqy-events` bus, condition `events:source = booqy.personalliggare` |
| cloudwatch-logs | logs:CreateLogStream, PutLogEvents | its own log group |
| (shared, via `wiring`) | tenant-context read policy (tenant, location tables) and staff-check read of the user table | attached by `config.tf` like every feature |

The hook callers' invoke grants on `personalliggare:live` (platform-tenants for
H9, tenant-purge) exist since Run 0 (CONTRACTS.md 14 rows 2 and 10).

## Unverified

- That the resource policy denies the Lambda role's Update/Delete in AWS and does
  **not** block TTL expiry deletes (ADR-H decision 7). If it does block TTL, a
  human decides on a narrow yearly purge exception.
