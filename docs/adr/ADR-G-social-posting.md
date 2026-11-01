# ADR-G: Organic Instagram and Facebook posting

**Status:** Proposed
**Date:** 2026-11-01
**Deciders:** Owner (product), orchestrator (contracts), ADR-A author (Meta connection)
**Run:** built in Run 2, after ADR-A (Run 1) is merged

## Context

Owners want to tell guests about a new dish or tonight's special without
opening Meta's tools. ADR-A already connects a tenant's Meta Business assets
(Facebook Page, Instagram professional account, ad account) through Facebook
Login for Business and keeps the token per tenant in Secrets Manager. Organic
posting needs the same connection, a few more permissions, a post store and a
scheduler. Menu items (`LOCATION#<l>/MENU#<id>`: name, description, price,
`imageKey`, `alcohol`) are the content source; images are in the menu-image
bucket under a tenant- and location-scoped key.

## Decision

1. **No new token storage.** G reads ADR-A's per-tenant connection
   read-only: the secret `booqy/<env>/meta-ads/<tenantId>` and the
   `TENANT#<t>/CONNECTION` item in `<prefix>meta-ads` (`status`, `pageId`,
   `instagramId?`). Token refresh, disconnect and asset
   choice stay in A. G's role has `GetSecretValue` only, never Put/Create.
2. **A's login asks for G's permissions too** (`pages_manage_posts`,
   `pages_read_engagement`, `instagram_basic`, `instagram_content_publish`),
   requested only when `socialPosting` is on (incremental consent). A's
   connection routes (`/tenant/meta-ads/connection/*`, `/tenant/meta-ads/assets`)
   must accept a tenant with `metaAds` OR `socialPosting` on. Both are now
   in ADR-A (decision 10, App Review list) and CONTRACTS.md 6.A.
3. **Meta calls go through A's Meta port** (`shared/meta_graph.py`:
   `MetaGraph`, `SimulatedMetaGraph`, factory on `META_CLIENT` from Terraform
   `meta_client`, simulator refused in prod; Run 0 scaffolding). G adds two methods to
   the port: `publish_page_photo(page_id, image_url, caption)` and
   `publish_instagram_image(ig_user_id, image_url, caption)` (container
   create, then `media_publish`). Mocked in Runs 1-3.
4. **One post, one or two channels**, each with its own state, so a post can
   succeed on Facebook and fail on Instagram without double-posting on retry.
5. **Scheduling** uses one-time EventBridge Scheduler schedules
   (`post-<postId>`, group `<prefix>social-posting`), the
   `catering-lifecycle` pattern. "Publicera nu" invokes the same path
   asynchronously.
6. **Idempotent publishing.** Per channel: conditional update `queued ->
   publishing` with a 5-minute lease, store Meta's id on success. Instagram:
   the container id is stored before `media_publish`, so a retry publishes
   the same container (Meta refuses a second publish of one container). Facebook
   has no idempotency key: on an unknown outcome (timeout after send) the
   channel goes to `needs_check` and the worker reads the Page's latest posts
   for the caption's marker hash before any retry. Never blind-retry.
7. **Drafts from menu items** are built from a Swedish template (name,
   description, price "149 kr"). A "Föreslå text" button reuses
   `shared/bedrock.py` `TextModel` (Run 0 scaffolding, `BEDROCK_CLIENT`)
   and counts against A's monthly `COPYUSE#<yyyy-mm>` quota; G adds no LLM
   client of its own.
8. **Images** are passed to Meta as a short-lived (15 min) presigned GET URL
   of the menu image; no bucket or CSP change.
9. **Alcohol:** dishes with `alcohol: true` get no automatic draft and need a
   confirmation checkbox (alkohollagen 7 kap., see legal notes).

## Data model

Table `<prefix>social-posting` (PAY_PER_REQUEST, PITR, deletion protection in
prod, TTL `ttl`).

| PK | SK | Item |
|---|---|---|
| `TENANT#<t>` | `POST#<postId>` | one post |

Post: `tenantId`, `postId` (client ULID), `locationId`, `source`
`{kind: dish|special|free, menuItemId?}`, `caption` (1-2,000 chars),
`imageKey` (must start with the tenant's and location's menu-image prefix),
`channels` `{facebook?: Channel, instagram?: Channel}`, `status`
(`draft` | `scheduled` | `publishing` | `published` | `partly_published` |
`failed` | `cancelled`), `scheduledAt?` (UTC ISO, now to +90 days),
`alcoholConfirmed?`, `createdBy`, `createdAt`, `updatedAt`, `version`,
`ttl` (published/cancelled/failed + 400 days; drafts none).

Channel: `state` (`queued` | `publishing` | `published` | `needs_check` |
`failed`), `leaseUntil?`, `containerId?` (IG), `metaPostId?`, `permalink?`,
`publishedAt?`, `attempts`, `lastError?` `{code, message}` (no tokens).

Listing: Query `PK=TENANT#<t>`, `begins_with(SK, POST#)` (ULIDs sort by
time). Volume is tiny (tens per month), so status filtering is in code. No GSI.

## API routes

All JWT, **owner only** (Marknadsföring is owner-only). `locationId` and
`menuItemId` are checked against the tenant (foreign -> 404).

| # | Method | Path | Request -> response |
|---|---|---|---|
| 1 | GET | `/tenant/social-posts?status=` | -> `{connection{page?, instagram?, missingPermissions[]}, posts[]}` |
| 2 | POST | `/tenant/social-posts` | `{postId, locationId, caption, imageKey, channels[], source}` -> 201 draft |
| 3 | POST | `/tenant/social-posts/drafts` | `{locationId, menuItemIds[1-10]}` -> `{posts[]}` (draft ids derived `<menuItemId>-<yyyymmdd>`) |
| 4 | GET | `/tenant/social-posts/{postId}` | -> post |
| 5 | PUT | `/tenant/social-posts/{postId}` | `{caption?, imageKey?, channels?, alcoholConfirmed?, version}` -> post (draft or scheduled only) |
| 6 | POST | `/tenant/social-posts/{postId}/schedule` | `{scheduledAt \| now: true, version}` -> post |
| 7 | POST | `/tenant/social-posts/{postId}/cancel` | `{version}` -> post (only before publishing) |
| 8 | DELETE | `/tenant/social-posts/{postId}` | -> 204 (draft only) |

Errors: 400 `caption_too_long`, `invalid_channels`, `invalid_schedule`,
`image_not_allowed`, `alcohol_confirmation_required`; 403
`feature_not_in_plan`, `owner_only`; 404 foreign/unknown post, location, menu
item or image key; 409 `changed_retry`, `invalid_state`, `meta_not_connected`,
`meta_permission_missing` (with `field: "instagram"` etc.).

Idempotency: `postId` client-supplied (Put `attribute_not_exists`, retry
returns the stored draft); drafts from menu use deterministic ids; state
changes are conditional on `version`; a second schedule with the same time
returns the current post and keeps one schedule (`create_schedule` on an
existing name is treated as success after comparing the time).

## Events

Bus `<prefix>booqy-events`, source `booqy.social-posting`. Detail: `tenantId`,
`occurredAt`, `version: 1`, `postId`, `locationId`.

| detail-type | extra detail |
|---|---|
| `SocialPost.Scheduled` | `scheduledAt`, `channels[]` |
| `SocialPost.Published` | `channel`, `metaPostId`, `permalink` |
| `SocialPost.Failed` | `channel`, `code` |

G consumes `MetaConnection.Disconnected` (ADR-A): a rule on the bus
targets the `social-posting` Lambda, which moves the tenant's `scheduled`
posts back to `draft` and deletes their schedules (idempotent, conditional on
status). The worker still checks the connection at publish time and fails the
channel with `meta_not_connected`, so a missed event is harmless.
`MetaConnection.Connected` needs no handling.

## Terraform modules

- `infrastructure/social-posting/`: table, Lambda `social-posting` (API
  routes and the scheduled publish target, one function), role, scheduler
  group `<prefix>social-posting`, invoke role, Errors alarm.
- Root `social-posting.tf`; routes `network/api-gateway/social-posting-routes.tf`.
- Env: `META_CLIENT` from A's validated variable `meta_client` (G does not
  declare its own; it reads `var.meta_client`). Simulator refused in prod.
- IAM (new role): its table, menu table `GetItem`/`Query` (read), menu-image
  bucket `s3:GetObject` under `<tenant>/*` for presigning,
  `secretsmanager:GetSecretValue` on `booqy/<env>/meta-ads/*` (read only,
  never the app secret's write), `dynamodb:GetItem` on the `<prefix>meta-ads`
  table (`CONNECTION` rows), scheduler on its group, `iam:PassRole`,
  `events:PutEvents`; an EventBridge rule on `MetaConnection.Disconnected`
  with a Lambda permission.
- Usual wiring through the module's `wiring` output (ECR repo by Run 0);
  purge is the `tenant.purge` hook.

## Entitlement name

`socialPosting`. Off -> 403 `feature_not_in_plan`. The scheduled worker
re-checks the entitlement and fails the channel with `feature_not_in_plan`
if it was switched off after scheduling.

## Plan availability (target)

growth (with marketing). Run 0 ships `false` in every plan.

## UI placement

- Admin, group `restaurangen`, `/marknadsforing?flik=inlagg`: new tab
  "Inlägg" (owner only), list with status chips ("Utkast", "Schemalagd",
  "Publicerad", "Delvis publicerad", "Misslyckades"), editor with Facebook
  and Instagram previews, "Publicera nu", "Schemalägg", "Avbryt".
  When Meta is not connected: "Koppla Facebook och Instagram" deep link to
  A's connect flow.
- Admin, `/meny`: owner-only "Dela" action on a dish -> creates a draft and
  opens the Inlägg tab.
- Console: only the generic feature checkbox.

## External dependencies

- Meta Graph API (Pages, Instagram content publishing): **mocked** in Runs
  1-3 via A's simulator.
- **Approval needed:** Meta App Review for `pages_manage_posts` and
  `instagram_content_publish` on top of A's Business Verification and
  review. Instagram publishing requires a professional account linked to
  the Page; the UI must say so.
- Rate limit: Instagram allows a limited number of API posts per 24 hours
  per account (verify the current figure); the worker returns
  `instagram_rate_limited` and does not retry until the window passes.

## Privacy and GDPR

- No guest data. Stored: captions, image keys, Meta post ids, the owner's
  `sub` as author. Legal basis for the owner's data: contract (6(1)(b)).
- Posting publishes the restaurant's content to Meta (controller: the
  restaurant; Meta is a separate controller for what is on its platform).
  The DPA should name Meta as a recipient when the tenant uses the feature.
- Retention: 400 days after publish/cancel via `ttl`; tenant-purge deletes
  all rows. Posts already on Meta are not deleted by Booqy.
- Storage registry: no new keys (admin or site-kit). No pixel, no SDK on any
  page.

## Swedish legal notes (human check)

- **Alcohol (alkohollagen 7 kap. 1 och 3 §§):** marketing alcoholic drinks
  to consumers needs "särskild måttfullhet" and must not target people under
  25; check whether organic posts about a drink on a restaurant's own
  accounts are in scope, and whether the confirmation checkbox is enough.
- **Prisinformationslagen:** a price in a post must be the full price incl.
  VAT (the template uses the menu price, which is incl. VAT).
- **Marknadsföringslagen:** posts must be identifiable as the restaurant's
  own marketing (they are posted from its own Page, so likely fine).
- Image rights: owners confirm they own the dish photo (terms text).

## Test plan

Two-tenant fixtures, `mock_aws()`, `SimulatedMetaGraph`. Each route: happy
path, validation error, wrong role, foreign tenant 404, entitlement off,
idempotent retry.

| # | Validation | Wrong role (staff) | Foreign 404 | Off | Retry |
|---|---|---|---|---|---|
| 1 | bad status filter 400 | 403 `owner_only` | only own posts listed | 403 | n/a |
| 2 | caption 2,001 chars; imageKey of B | 403 | locationId of B | 403 | same postId -> same draft |
| 3 | 11 menu items; alcohol dish skipped | 403 | menuItemId of B | 403 | same day -> same ids, no duplicates |
| 4 | bad id 400 | 403 | postId of B | 403 | n/a |
| 5 | edit a published post 409 | 403 | postId of B | 403 | stale version 409 |
| 6 | time in the past / +91 days | 403 | postId of B | 403 | same time -> one schedule |
| 7 | cancel published 409 | 403 | postId of B | 403 | second cancel -> same post |
| 8 | delete scheduled 409 | 403 | postId of B | 403 | second delete 204 |

Disconnect event handled twice -> same drafts, no schedules left. Worker: run twice for one post -> one Meta call per channel; crash after IG
container create -> retry reuses the container; FB timeout -> `needs_check`,
no second post; one channel fails, the other is published
(`partly_published`), retry touches only the failed one; entitlement switched
off before the timer -> failed, no Meta call; Meta disconnected -> failed
`meta_not_connected`. Isolation: tenant A's worker can never read B's secret
(secret id built from the post's `tenantId`, asserted). UI: light and dark,
mobile, tablet, desktop.

## Alternatives considered

- **Own Meta token per feature:** two tokens for one Page, two refresh
  paths, double App Review surface. Rejected (and the brief says no).
- **Meta's own scheduled publishing** (`scheduled_publish_time` on Pages):
  Facebook only, Instagram has no equivalent through the same call; one
  Booqy scheduler keeps both channels identical. Rejected.
- **Bedrock captions by default:** costs per draft and needs review; the
  template is enough for v1.

## Open questions

1. ADR-A must add `pages_manage_posts` and `instagram_content_publish` to
   its login configuration and App Review, and accept `socialPosting` on its
   connection routes: confirm in CONTRACTS.md. Note the `meta-ads` secret
   name now serves two features.
2. Carousel posts or Stories? v1 is one image per post.
3. Should staff be allowed to draft (not publish)? v1: owner only.
4. Repost when a dish is reactivated? Not in v1.
