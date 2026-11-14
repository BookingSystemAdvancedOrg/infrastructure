# ADR-B: Site builder (Utkast/Publicerad, AI edits, custom-code tier)

**Status:** Proposed
**Date:** 2026-11-01
**Deciders:** Owner (product), orchestrator (contracts)
**Run:** B1 (schema, editor, publish, rollback) in Run 1; B2 (AI edits, custom-code tier) in Run 2

## Context

Every restaurant gets `<slug>.booqy.se` (BR-BOOQY-038) and a private repo
`site-<slug>` that deploys to `sites/<tenantId>/` in the sites bucket through
a deploy role bound by the fixed permissions boundary (BR-BOOQY-043,
BR-NFR-006). The tenant-sites multi-tenant CloudFront distribution serves
that folder (`origin_path=/sites/{{tenantId}}`, SPA fallback) when
`per_tenant_sites` is on, else the shared customer-site SPA. Owners can only
change branding today (colours, logo, texts); anything else needs a
developer. site-kit already renders menu, booking, ordering, catering and
legal pages from `/site-config`, and has contrast helpers (`accentPair`,
BR-NFR-034).

## Decision

1. **One versioned JSON document per tenant** (`schemaVersion: 1`), JSON
   Schema in `application/shared/site_schema/v1.json`, the single source for
   Python validation and generated TS types in site-kit. Shape:
   `{schemaVersion, theme{primaryColor, accentColor, font: serif|sans},
   nav[{pageId}], pages[{id, slug, title, seo{title, description},
   blocks[{id, type, ...props}]}], footer{text}}`. Block types (v1, 10):
   `hero`, `text`, `image`, `gallery`, `menu` (live from the menu API),
   `openingHours` (live), `bookingCta`, `orderCta`, `cateringCta`, `contact`.
   Limits: 20 pages, 40 blocks per page, 150 KB document, images only by key
   in the tenant's menu-image prefix, links only to own pages or `https:`.
2. **Draft + immutable versions + published pointer** in DynamoDB. The draft
   is edited with optimistic `version`. Publish creates `VERSION#<n>`
   (never updated), then swaps `PUBLISHED` with a condition on the previous
   pointer. Rollback = publish an older version again (pointer swap only, no
   re-render).
3. **Publish is a Step Functions workflow** `<prefix>site-builder-publish`:
   Validate (schema, links, image keys, contrast: theme pairs nudged with the
   same algorithm as site-kit `accentPair`, shared test vectors; any text
   pair still under 4.5:1 fails with a field path) -> Render -> Promote ->
   Done. **Render** is a Node Lambda `site-builder-render` that runs
   site-kit's own components with `react-dom/server` (one renderer, no drift)
   and writes `sites/<t>/v/<n>/<page>/index.html` + `site.json` +
   hashed assets (immutable, `Cache-Control: max-age=31536000, immutable`).
   **Promote** copies each page's `index.html` to `sites/<t>/<page>/index.html`
   (server-side CopyObject, `Cache-Control: no-cache`), deletes root pages no
   longer in the version, then writes `PUBLISHED`. Each page object is one
   atomic PUT and references only its own version's assets, so a guest never
   sees a broken page; during the seconds of promotion pages may come from
   two adjacent versions. Live data (hours, booking, menu) still comes from
   `/site-config` and the existing APIs at runtime.
4. **site-kit renders the published document**: the pre-rendered HTML embeds
   `site.json`; `/site-config` gains `tenant.site = {mode, version}` (shared
   hotspot, Run 0) so a stale tab can reload. The site-builder Lambda
   mirrors `{mode, version}` onto `TENANT#<t>/PROFILE.site` (UpdateItem
   limited to that attribute); site-config passes it through. Tenants not in builder mode
   keep today's behaviour.
5. **Private preview link**: owner creates a token (32 random bytes, stored
   as SHA-256, 7 days). URL `https://<host>/forhandsvisning#<token>`; the
   token stays in the fragment (never in logs) and site-kit posts it to the
   public preview route, which returns the current draft. Preview pages send
   `noindex`.
6. **Site mode** on the tenant's builder row: `builder` (default once the
   feature is on) or `custom`. One mode at a time owns `sites/<t>/` root.
7. **B2 AI edits**: owner prompt (max 500 chars) + current draft -> Bedrock
   (`shared/bedrock.py` port, `BEDROCK_CLIENT`) -> an RFC 6902 JSON Patch
   restricted to `/pages/*` and `/theme/*` -> server applies to a copy,
   validates the schema and contrast -> returns `{patch, before, after}`.
   Admin renders before and after with site-kit side by side (the visual
   diff); "Använd ändringen" applies the same patch to the draft only if the
   draft `version` is unchanged. Quota: `entitlements.limits.siteBuilderAiEditsPerMonth`,
   counted per generated proposal with an atomic ADD conditioned on
   `count < limit` (missing limit = 0).
8. **B2 custom-code tier** on the existing `site-<slug>` repo, Booqy staff
   only. The template workflow changes (owner's `.github`, snippet in the
   build hand-off): PR builds deploy to `sites/<t>/preview/<commitSha>/`,
   `main` builds deploy to `sites/<t>/releases/<commitSha>/`; **the repo no
   longer writes the root**. The deploy role and permissions boundary are
   unchanged (still only `sites/<tenantId>/*`). In the console, staff mark a
   release "Ready for owner"; this creates a draft-like `CUSTOM#<sha>` item.
   The owner sees the same Utkast/Publicerad buttons: "Förhandsgranska" opens
   the preview prefix, "Publicera" runs the same workflow with
   `source: custom` (Validate checks the prefix exists and has `index.html`;
   Render is skipped), Promote copies `releases/<sha>/` to root and records
   `VERSION#<n>` with `source: custom`. Rollback works the same for both.

## Data model

Table `<prefix>site-builder` (PAY_PER_REQUEST, PITR, deletion protection in
prod, TTL `ttl`). No GSI.

| PK | SK | Item |
|---|---|---|
| `TENANT#<t>` | `SITE` | `mode` (`builder` \| `custom`), `version` |
| `TENANT#<t>` | `DRAFT` | `doc`, `schemaVersion`, `basedOn` (version n), `version`, `updatedAt`, `updatedBy` |
| `TENANT#<t>` | `VERSION#<n:06d>` | `doc?` (builder), `source` (`builder` \| `custom`), `commitSha?`, `prefix` (`v/<n>/` or `releases/<sha>/`), `pages[]`, `contrast[]`, `publishedAt`, `publishedBy`; written with `attribute_not_exists`, never updated |
| `TENANT#<t>` | `PUBLISHED` | `versionNo`, `previousNo`, `publishId`, `publishedAt`, `version` |
| `TENANT#<t>` | `PUBLISH#<publishId>` | `status` (`running` \| `done` \| `failed`), `versionNo?`, `kind` (`publish` \| `rollback`), `error?{code, field}`, `executionArn`, `ttl` = +90 days |
| `TENANT#<t>` | `PREVIEW#<tokenHash>` | `createdBy`, `expiresAt`, `ttl` = +7 days |
| `TENANT#<t>` | `AIUSE#<yyyy-mm>` | `count`, `ttl` = +13 months (B2) |
| `TENANT#<t>` | `AIPROP#<proposalId>` | `patch`, `draftVersion`, `prompt`, `ttl` = +24 h (B2) |
| `TENANT#<t>` | `CUSTOM#<commitSha>` | `prNumber?`, `status` (`ready` \| `published` \| `withdrawn`), `markedBy`, `markedAt`, `ttl` = +180 days unless published (B2) |

S3 (existing sites bucket): `sites/<t>/v/<n>/...`, `sites/<t>/releases/<sha>/...`,
`sites/<t>/preview/<sha>/...`, root pages `sites/<t>/<page>/index.html`.
Preview cleanup: a nightly site-builder task deletes `preview/<sha>/`
prefixes older than 30 days. No bucket lifecycle rule: S3 lifecycle
prefixes cannot wildcard the tenant id, and a tag filter would need
`s3:PutObjectTagging`, which the fixed deploy boundary does not grant.

## API routes

Errors `{error, code, field?}` (`field` is a JSON pointer into the doc). All
JWT routes **owner only**; staff 403 `owner_only`.

| # | Method | Path | Auth | Role | Request -> response |
|---|---|---|---|---|---|
| 1 | GET | `/tenant/site-builder` | JWT | owner | -> `{mode, draft{doc, version, basedOn}, published{versionNo, publishedAt}?, aiQuota?}` |
| 2 | PUT | `/tenant/site-builder/draft` | JWT | owner | `{doc, version}` -> draft; 409 `changed_retry` |
| 3 | POST | `/tenant/site-builder/preview-links` | JWT | owner | `{}` -> `{url, expiresAt}` |
| 4 | POST | `/tenant/site-builder/publish` | JWT | owner | `{publishId, draftVersion}` or `{publishId, source: custom, commitSha}` -> 202 `{publishId, status}` |
| 5 | GET | `/tenant/site-builder/publish/{publishId}` | JWT | owner | -> `{status, versionNo?, error?}` |
| 6 | GET | `/tenant/site-builder/versions` | JWT | owner | -> `{versions[{versionNo, source, publishedAt, publishedBy, live}]}` |
| 7 | POST | `/tenant/site-builder/rollback` | JWT | owner | `{publishId, versionNo}` -> 202 `{publishId}` |
| 8 | POST | `/public/site-builder/preview` | token + request guard | guest | `{tenantId, token}` -> `{doc}`; 404 on any bad token |
| 9 | POST | `/tenant/site-builder/ai-edits` | JWT | owner | `{proposalId, prompt, draftVersion}` -> `{patch, before, after, quota{used, limit}}` (B2) |
| 10 | POST | `/tenant/site-builder/ai-edits/{proposalId}/apply` | JWT | owner | `{draftVersion}` -> draft (B2) |
| 11 | GET | `/platform/tenants/{tenantId}/site-builder` | operator | platform_admin | -> `{mode, published, releases[{commitSha, prNumber, previewUrl, status}]}` (B2) |
| 12 | PUT | `/platform/tenants/{tenantId}/site-builder/mode` | operator | platform_admin | `{mode, version}` -> `{mode}` (B2, audit row) |
| 13 | POST | `/platform/tenants/{tenantId}/site-builder/custom/{commitSha}/ready` | operator | platform_admin | `{}` -> CUSTOM item (B2, audit row) |

Errors: 400 `unsupported fields`, `schema_invalid`, `contrast_too_low`,
`doc_too_large`, `invalid_link`, `unknown_image`, `invalid_patch`,
`prompt_too_long`; 403 `feature_not_in_plan`, `owner_only`; 404 unknown or
foreign publish, version, proposal, token, release; 409 `changed_retry`,
`publish_running` (one at a time per tenant), `wrong_mode`; 429
`quota_exceeded`; 502 `ai_unavailable`. Route 5 `error.code` is one of the
400 codes above or `start_failed` (StartExecution failed after the
`PUBLISH#` row was written; routes 4 and 7 with the same `publishId` start
it again). A page `slug` the customer app routes itself or an S3 prefix
(`v`, `releases`, `preview`, `assets`) is 400 `schema_invalid` at
`/pages/<i>/slug` (`RESERVED_SLUGS`, CONTRACTS.md 6.B).

Idempotency: `publishId` / `proposalId` are client ULIDs (conditional Put;
execution name = `publishId`, so a retry returns the same status); draft
and pointer writes are conditional on `version`; rollback to the live
version is a 200 no-op.

## Events

Bus `<prefix>booqy-events`, source `booqy.site-builder`. Every detail has
`tenantId`, `occurredAt`, `version: 1`.

| detail-type | extra detail |
|---|---|
| `SiteVersion.Published` | `versionNo`, `previousNo?`, `source`, `kind` (`publish` \| `rollback`) |
| `SitePublish.Failed` | `publishId`, `code` |
| `SiteRelease.Proposed` | `commitSha` (B2) |

## Terraform modules

- `infrastructure/site-builder/`: table, Lambdas `site-builder` (Python API
  + workflow tasks Validate/Promote, nightly preview cleanup) and
  `site-builder-render` (Node 22 image), state machine
  `<prefix>site-builder-publish`, logs, alarms, roles. Root
  `site-builder.tf`; routes
  `network/api-gateway/site-builder-routes.tf`; operator routes on the
  `platform` authorizer handled by `platform-tenants`.
- **IAM change (call out):** the two new roles get `s3:PutObject`,
  `GetObject`, `DeleteObject`, `ListBucket` (prefix `sites/`) on the sites
  bucket; tenant scoping is in code (key built from the JWT tenant). The
  deploy roles, `deploy_boundary` and OIDC roles are **not** changed.
- Render image: built from customer-front-end (`render-lambda/`), pushed to
  the `site-builder-render` ECR repo created by Run 0; released like the
  console API Lambda.
- The module's `wiring` output lists the functions; purge is the
  `tenant.purge` hook (tenant-purge already deletes `sites/<t>/` through
  site-repo). Operator routes 11-13 are forwarded by `platform-tenants`.

## Entitlement name

`siteBuilder` (`entitlements.features.siteBuilder`); B2 quota is the limit
`entitlements.limits.siteBuilderAiEditsPerMonth` (integer). Off -> 403 on
JWT routes, 404 on route 8. The custom-code tier is not a plan feature: an
operator sets `mode=custom`.

## Plan availability (target)

`siteBuilder`: starter and growth. `siteBuilderAiEditsPerMonth`: starter 10,
growth 50. Run 0 ships `siteBuilder=false` and the limit 0 everywhere.

## UI placement

- Admin, group `restaurangen`, new item `/webbplats` "Webbplats"
  (feature `siteBuilder`, ownerOnly): header with "Utkast" / "Publicerad"
  status and buttons "Förhandsgranska", "Dela förhandsvisning", "Publicera";
  left block list (add, move, delete), right live site-kit preview at
  mobile/desktop width; "Versioner" drawer with "Återställ". B2: "Ändra med
  AI" box (quota "7 av 10 kvar i november"), before/after view, "Använd
  ändringen" / "Släng". In custom mode the editor is replaced by the ready
  release card with the same buttons.
- Guest site: `/forhandsvisning` (preview), pages from the document.
- Console: TenantPage Website tab gains "Site mode" and (B2) the releases
  list with "Ready for owner".

## External dependencies

Bedrock (B2, mocked behind `TextModel`); GitHub via existing `site-repo`
(simulated outside prod). No new approvals beyond Bedrock model access.

## Privacy and GDPR

- Data: restaurant content only (no guest data); `publishedBy`/`updatedBy`
  are staff `sub`s. Prompts may hold whatever the owner types: the UI says
  "Skriv inga personuppgifter", proposals expire in 24 h.
- Retention: versions kept while the tenant exists (owner may need old
  content); preview tokens 7 days; S3 previews 30 days.
- Erase: tenant-purge removes rows and `sites/<t>/`.
- Storage registry: site-kit `PREVIEW_TOKEN` is not stored (fragment only);
  admin editor keeps no browser storage (draft saved on the server). No
  cookies. Pre-rendered pages load the same CSP meta as the customer site.

## Swedish legal notes (human check)

- Owner-written content on the site (prices incl. VAT, alcohol wording,
  image rights): the owner is responsible; confirm the editor's notice text.
- AI-generated text: confirm no labelling duty applies to restaurant site copy
  (EU AI Act art. 50 deployer duties).

## Test plan

Two-tenant fixtures, `mock_aws()`, `SimulatedTextModel`. Every route:
happy path, validation error, wrong role, foreign tenant 404, entitlement off
refused, idempotent retry.

| # | Validation | Wrong role | Foreign 404 | Off | Retry |
|---|---|---|---|---|---|
| 1 | n/a | staff 403 | own tenant only | 403 | n/a |
| 2 | bad block type, 151 KB | staff 403 | n/a | 403 | stale version 409 |
| 3 | unknown field | staff 403 | n/a | 403 | new token each call |
| 4 | a 3:1 theme colour is nudged to >= 4.5:1 and recorded in `contrast[]` (no 400); unknown image | staff 403 | B's commitSha 404 | 403 | same publishId -> same execution; a `start_failed` row is restarted |
| 5 | bad id 400; `error.code = start_failed` when StartExecution failed | staff 403 | B's publishId 404 | 403 | n/a |
| 6 | n/a | staff 403 | n/a | 403 | n/a |
| 7 | version 999 404 | staff 403 | B's version 404 | 403 | same publishId once; live version no-op |
| 8 | malformed token 404 | n/a | A's token with B's tenantId 404 | 404 | n/a |
| 9 | patch outside `/pages`, 501-char prompt | staff 403 | n/a | 403 / limit 0 -> 429 | same proposalId counted once |
| 10 | draft changed 409 | staff 403 | B's proposal 404 | 403 | second apply 200 same draft |
| 11-13 | bad mode, bad sha | tenant JWT refused | unknown tenant 404 | n/a | repeat gives same result |

Plus: workflow idempotent (rerun Promote: same objects) and resumable (fail
after Render, redrive); rollback never re-renders; root never references
another tenant's prefix; render output of every block matches site-kit
client render (snapshot); contrast vectors identical in Python and TS;
`contrast_too_low` is a safety net that the nudge (decision 3) makes
unreachable for any valid hex colour, so it is tested by stubbing
`accent_pair`, not with a 3:1 input (DECISIONS.md 2026-11-03); UI at
mobile/tablet/desktop, light/dark, keyboard-reorderable blocks. **Two-tenant
isolation test:** A publishes; every S3 key written starts with
`sites/<A>/`; A's routes with B's ids 404; B's site unchanged.

## Alternatives considered

- **CloudFront KeyValueStore + function rewriting to `v/<n>/`**: a truly
  atomic pointer, but new edge code on the multi-tenant distribution and
  key upkeep per host. Kept as the upgrade path if mixed-version seconds matter.
- **Python template renderer**: no Node Lambda, but a second renderer that
  drifts from site-kit. Rejected.
- **Client-only render from `site.json`**: simplest, but no HTML for search
  engines and slower first paint. Rejected.
- **Custom repo keeps writing root on `main`**: bypasses Utkast/Publicerad
  and rollback. Rejected.

## Open questions

1. Render Lambda image built in the customer-front-end pipeline: owner to
   confirm (`.github` snippet needed).
2. Should builder-mode tenants fall back to the shared customer-site SPA
   when nothing is published yet? v1: yes, `PUBLISHED` missing = today.
3. Max versions kept (all, or last 50)?
