# ADR-A2: Ads on all platforms behind one adapter port (addendum to ADR-A)

**Status:** Proposed (spec only; nothing built, every new key off by default)
**Date:** 2026-11-04
**Deciders:** Owner (product, plans, which platforms, money-screen rule); orchestrator (contracts); per platform the external review bodies named below
**Run:** A2 in Run 2 (port, Meta adapter, spend confirmation, schedules, guide, daily view); A3 Google Ads and A4 TikTok in Run 3 against simulators, real adapters only after the platform approvals. **No run of its own** (see "Run plan").

This addendum widens ADR-A from Meta to every ad platform whose API lets
Booqy create ads on a restaurant's own account. ADR-A's decisions stay as
built on `dev` (Run 1); this file adds a port in front of them, states
what each platform needs, and fixes the owner's requirements of
2026-11-04 (PIPELINE.md): guided account connection, restaurant-set
spend inside the existing caps, recurring and scheduled campaigns,
first-time guide, daily view, plain-language tracking, brand only.
Anything marked **[NEEDS YOUR OK]** is a proposal.

## Context

Run 1 built Meta ads end to end: Login for Business, asset picker, the
six-step wizard, the publish state machine, kill switch, monthly cap,
80 %/100 % spend rules, UTM attribution and nightly insights. All of it
is platform-neutral except the five Meta Graph calls inside the publish
workflow, the insights fetch and the connection routes; those call
`shared/meta_graph.MetaGraph` directly. Routes, table keys, events,
secrets and the entitlement are named `meta-ads`/`metaAds`.

The owner's words: ads on all platforms, a pleasant UI to connect the
social accounts and automate the ads, the restaurant sets the spend,
idiot-proof navigation, first use and daily use, tracking, and the
Booqy brand throughout.

Hard rules stay: no pixel or conversions API on any platform (BR-NFR-011,
BR-GUEST-046), no guest data to any platform, spend bounded even if Booqy
misbehaves, Swedish copy, owner-only money unless the owner decides
otherwise (flagged below).

## Decision

1. **One port, `AdPlatform` (`shared/ad_platform.py`), one adapter per
   platform, chosen by the campaign's `platform`.** Methods (every id
   idempotent by a Booqy-chosen name, like `MetaGraph`):

   | Method | Purpose |
   |---|---|
   | `capabilities() -> Capabilities` | what the platform can do: `budget` (`lifetime` \| `daily_with_end`), `creative` (`image`, `video`, `image_to_video`), `minBudgetSek`, `radiusTargeting`, `dsaFields`, `previewUrl`, `scheduledStart` |
   | `authorize_url(state, redirect_uri, scopes)`, `exchange_code(code, redirect_uri) -> Token` | the platform's OAuth; `Token` carries `expires_at` and `refresh` when the platform rotates |
   | `list_assets(token) -> Assets{accounts[{id, name, currency, has_payment_method}], pages?, profiles?, missing[{kind, deepLink}]}` | the picker; a missing item is a typed step with the platform's deep link, never an error |
   | `upload_creative(token, account, Creative) -> creative_ref` | image (or video) upload |
   | `create_campaign(token, account, CampaignSpec) -> PlatformIds` | the platform's whole object chain (campaign, ad set/group, ad) in one adapter call that is itself resumable: every object is named `booqy-<campaignId>-<step>` and looked up before it is created; created **paused** |
   | `set_status(token, ids, status)` | activate, pause |
   | `insights(token, account, campaign_ids, day) -> rows` | spend, reach, clicks per campaign and day |
   | `preview_url(token, ids) -> url \| None` | when the platform has one |
   | `revoke(token)` | disconnect |

   `MetaAdPlatform` wraps the Run 1 `MetaGraph` (its `create_campaign`
   runs the five existing calls); the publish state machine keeps its
   shape but its tasks call the adapter, so Meta's behaviour on `dev`
   does not change. Simulators: `SimulatedAdPlatform(platform)` reuses
   `SimulatedMetaGraph`'s conventions (ids `sim-<platform>-<kind>-<sha1>`,
   deterministic insights, `fail=` injection, `missing=`). Factory from
   one env var per platform (`GOOGLE_ADS_CLIENT`, `TIKTOK_ADS_CLIENT`,
   like `META_CLIENT`), simulator refused in prod.

2. **Order and gate: Meta (built), then Google Ads, then TikTok, then
   others only if their API lets a third party create ads on the
   restaurant's own account.** The table is what the Run 3 builder and
   the owner start from; "cost" is Booqy's cost (every platform bills the
   media spend to the restaurant's own ad account, never to Booqy).

   | Platform | API access | Approval and who applies | Ad rules that bind the wizard | Cost | Decision |
   |---|---|---|---|---|---|
   | Meta (Facebook, Instagram) | Marketing API, Login for Business | Business Verification of Booqy, App Review for `ads_management`, `ads_read`, `business_management`, `pages_show_list`, `pages_read_engagement`, `instagram_basic` (ADR-A, human action, open) | DSA beneficiary/payor, 18+, alcohol refused in v1, lifetime budget with end date | API free; media spend on the restaurant's ad account | built (Run 1); adapter in Run 2 |
   | Google Ads (Search, Performance Max with store goals, Demand Gen incl. YouTube) | Google Ads API with a **developer token** from a Booqy manager account (MCC) and an OAuth 2.0 client whose consent screen Google verifies (scope `adwords`). Access levels: Test (test accounts only) -> Explorer (2 880 operations/day on production accounts) -> Basic (15 000/day) -> Standard (unlimited, review about 10 business days). Basic and Standard require **brand verification** of Booqy (policy change 2026). | Owner: manager account, developer token, access-level application and brand verification; OAuth app verification. The restaurant links its Google Ads account to Booqy's manager account (link invitation accepted in the restaurant's account) or grants OAuth as a user **[NEEDS YOUR OK: manager link (recommended, one consent, works when the restaurant has no Google login at hand) or per-user OAuth]** | daily budget + `end_date` (no lifetime budget: the adapter sets daily = total / days and the end date, and the nightly insights stop the campaign at the total if Google overdelivers past the cap); location targeting by radius around the address; alcohol: Google allows it in Sweden with restrictions, **refused in v1 like Meta**; Performance Max needs a Business Profile link for store goals (ADR-D) | API free; media spend on the restaurant's account | **A3, Run 3** (simulator in Run 3; real adapter after Basic access) **[NEEDS YOUR OK]** |
   | TikTok (TikTok for Business) | Marketing API: a developer app in the TikTok for Business developer portal (`app_id`/`secret`), scopes Ads Management, Reporting, Creative Management; OAuth 2.0 advertiser authorization (`auth_code` -> token per advertiser) | App review plus TikTok's data-security compliance check (owner applies); the restaurant needs a TikTok Ads Manager account with a payment method | **video creative required** (the wizard's dish photo must become a video: TikTok's Smart Video / image-to-video, or the owner uploads a 9:16 clip) **[NEEDS YOUR OK: ship TikTok only with image-to-video, or require an uploaded video]**; lifetime budget with schedule supported; 18+; alcohol refused in v1 (TikTok forbids it in most markets anyway); music rights only from TikTok's commercial library | API free; media spend on the restaurant's account | **A4, Run 3** behind a simulator; real adapter after app review **[NEEDS YOUR OK]** |
   | Snapchat (Snap Ads) | Marketing API, OAuth, Business account | Developer application (owner), business verification of the restaurant's ad account | vertical video or single image, lifetime budget supported, 18+ | API free | candidate after A4, only on demand **[NEEDS YOUR OK]** |
   | Pinterest Ads | Ads API, OAuth, business account; trial then standard access by application | Developer application (owner) | image ads fine, lifetime budget supported | API free | candidate after A4, only on demand **[NEEDS YOUR OK]** |
   | LinkedIn, X, Reddit | APIs exist but are B2B/restricted/weak on local radius | | | | **not suitable** for a restaurant's local ads; not planned |
   | Spotify, local radio/print | no public API for third-party ad creation | | | | **not possible**; not planned |

3. **Connecting an account: one guided flow per platform, plain
   Swedish, a clear fix for everything missing.** Admin "Annonser"
   gains a "Konton" card listing every platform the plan allows with
   `status` (`not_connected` \| `connected` \| `needs_reauth` \|
   `missing_steps`), and per platform a guide of numbered steps the
   restaurant can read before clicking (what they need: an existing
   account on that platform, a payment method there, who must be admin),
   then "Koppla <plattform>" (top-level redirect, no SDK, CSP unchanged).
   After the callback the asset picker shows what was found and every
   missing item as a step with the platform's deep link and the sentence
   that tells the restaurant what to do there ("Lägg till ett betalkort
   hos Meta, kom sedan tillbaka hit"), the same `missing[{kind,
   deepLink}]` pattern ADR-A built. A connection that stops working shows
   as "Behöver kopplas igen" with one button. Copy per platform lives
   in `src/features/meta-ads/guides/<platform>.ts` (A's folder) and is
   reviewed by design:ux-copy.

4. **Spend: the restaurant chooses and changes it per campaign and per
   platform, always inside the existing bounds, and nothing spends
   before an explicit confirmation that shows the total.** Bounds stay
   ADR-A 6: 100-20 000 SEK per campaign, the owner's monthly cap
   (default 3 000 SEK, platform ceiling from the console), the kill
   switch (platform, tenant) and the 80 %/100 % spend rule, now **summed
   over all platforms** per month (`SPEND#<yyyy-mm>` gains `byPlatform`).
   Confirmation is enforced server-side: activate (A11) and the schedule
   routes take `confirmedTotalSek` and answer 400 `total_mismatch` when
   it differs from what the campaign (or the schedule's maximum) would
   spend, so the UI cannot start spend without having shown the number.
   The confirmation screen says, in one sentence, the total, the
   platform, the days and what is left of the month's cap ("Meta drar
   högst 1 500 kr under 10 dagar. Kvar av månadens tak efteråt: 1 200
   kr."). Changing the spend of a running campaign is a pause plus a new
   campaign (platform budgets are not edited in place in v1) **[NEEDS
   YOUR OK]**. Spend alarm `Booqy/Ads PlatformSpendSek` per platform
   replaces the Meta-only metric.

5. **Recurring and scheduled campaigns.** A `SCHEDULE#<scheduleId>`
   holds a campaign template (platform, goal, creative, budget per run,
   days per run, radius), a cadence (`weekly` on a weekday, `monthly` on
   a day, or `once_at` a date) and limits. Each run creates a new
   campaign from the template through the normal publish workflow and
   **activates it without a new confirmation** (that is the automation),
   because the confirmation at schedule creation showed the maximum
   total of the whole schedule (runs x budget per run) **[NEEDS YOUR OK:
   auto-activate each run, or confirm every run by email link]**.
   Limits (constants in the module): at most **4 active schedules per
   location**, at most **12 runs** per schedule or an end date at most
   **6 months** ahead, one run of a schedule at a time, budget per run
   inside the campaign bounds. A run is skipped (not queued) and the
   owner emailed (`meta-ads.schedule-skipped`) when the month's cap would
   be exceeded, the kill switch is on, the connection needs re-auth, or
   the previous run failed; the schedule **stops itself** after 3
   consecutive skipped or failed runs, at its end date or last run, when
   the owner pauses it, when the connection is removed, and when the
   feature is turned off. Runs are idempotent by `<scheduleId>#<date>`
   (campaign id derived, one campaign per run day) and driven by the
   existing 15-minute sweep in `meta-ads-jobs`.

6. **Non-technical use: first-time guide, daily view, plain tracking,
   one next action per screen.** (a) First time on Annonser: a
   three-screen guide (what an ad here does, what it costs and that
   nothing is spent without confirmation, how to connect an account),
   ending in the first obvious action ("Koppla Meta"); shown until the
   first campaign exists, re-openable from the tab. (b) **Idag**: the
   top of the tab is a daily view of what runs now per platform, spend
   today and this month against the cap as a Bar meter, and a "Behöver
   din uppmärksamhet" list (ad rejected by the platform, connection to
   renew, cap at 80 %, run skipped) where each item has exactly one
   button. (c) Tracking per campaign and platform in plain language:
   "Visad för 4 200 personer, 180 klick, 9 bokningar. Varje bokning
   kostade 38 kr." from the existing UTM counters, with a per-platform
   total on the Översikt tiles. (d) Every screen has one primary action
   and the wizard keeps its six steps; the platform is step 0 only when
   more than one is connected. Navigation unchanged: everything lives
   under Marknadsföring > Annonser.

7. **Brand.** `packages/brand` only (tokens, glass, Bar family for the
   spend meter, progress and tabs, effects, and sound only if the brand
   package provides it: the feature adds none), light and dark, Swedish
   copy, checked at mobile, tablet and desktop by the brand guardian with
   Playwright screenshots. The review adds a **usability check against a
   first-time restaurant owner** (a scripted walkthrough: connect, first
   ad, read the daily view, pause) with findings ranked like code
   findings. A spend-meter Bar variant is requested from the brand
   guardian if the family lacks one; nothing hand-rolled.

8. **Money screens: FLAG for the owner.** Today marketing is owner-only
   (`owner_only` on every A route) and staff never see amounts
   (`without_money`). The owner's words "the user in the restaurants
   should have access to add the amount spent" may mean the owner or
   also staff. This ADR keeps the existing rule (owner-only, amounts
   hidden from staff) until the owner decides. **[NEEDS YOUR OK, pick
   one]** (a) keep owner-only; (b) let the owner name staff users as
   "marknadsförare" who may create and activate campaigns up to a
   per-campaign limit the owner sets, with amounts visible to them only;
   (c) staff see campaign results without amounts, owner keeps spend.
   Option (b) is a contract change (a new per-user flag on the user row,
   a hotspot) and would be scheduled for Run 3.

## Contract sketch (final rows written into CONTRACTS.md at the Run 2 cut, Fable)

Meta's A1-A17, table, events and entitlement stay as built. Additions,
all under feature A's ownership (`meta-ads` ids keep their names; the
platform-neutral prefix is `ads` in paths only):

| # | Method + path | Auth | Request -> response |
|---|---|---|---|
| A18 | GET `/tenant/ads/platforms` | jwt owner | -> `{platforms[{platform, status, assets?, missing[], guide}]}` |
| A19 | POST `/tenant/ads/platforms/{platform}/connection/start` | jwt owner | `{}` -> `{authorizeUrl}` (Meta: forwards to A2) |
| A20 | POST `/tenant/ads/platforms/{platform}/connection/callback` | jwt owner | `{code, state}` -> connection |
| A21 | DELETE `/tenant/ads/platforms/{platform}/connection` | jwt owner | -> 204 (pauses that platform's campaigns and schedules) |
| A8' | A8 body gains `platform` (default `meta`) and the creative kind the platform needs; 400 `creative_kind_required` | | |
| A11' | A11 body gains `confirmedTotalSek`; 400 `total_mismatch` | | |
| A22 | PUT `/locations/{locationId}/ads/schedules/{scheduleId}` | jwt owner | template + cadence + `confirmedTotalSek` + `version?` -> schedule; 400 `invalid_cadence`, `too_many_runs`, `total_mismatch`; 409 `too_many_schedules` |
| A23 | GET `/locations/{locationId}/ads/schedules` | jwt owner | -> `{schedules[]}` with next run, runs done, why stopped |
| A24 | POST `/locations/{locationId}/ads/schedules/{scheduleId}/pause` | jwt owner | `{version}` -> schedule |
| A25 | GET `/locations/{locationId}/ads/today` | jwt owner | -> `{running[], spendTodaySek, spendMonthSek, capSek, attention[{kind, campaignId?, platform, action}]}` |
| A13' | insights rows gain `platform`; totals per platform | | |

Data: `CONNECTION` stays Meta's row; `CONNECTION#<platform>` for the
others; `CAMPAIGN#` gains `platform` and `scheduleId?`; `SCHEDULE#<id>`;
`SPEND#<month>.byPlatform`; secrets `booqy/<env>/ads/<platform>/<tenantId>`
(Meta keeps `booqy/<env>/meta-ads/<t>`). Events: `MetaCampaign.*` stay;
new `AdCampaign.Created|Activated|Paused` with `platform` for the other
platforms, `AdSchedule.Run` and `AdSchedule.Stopped` (`reason`). Enum
`AdPlatform: [meta, google, tiktok]`. Entitlements **[NEEDS YOUR OK]**:
keep `metaAds` as the Annonser entitlement, add `googleAds` and
`tiktokAds` when their adapters ship (Annonser shows with any of them;
plan matrix rows false until the owner sets them); or one `ads` key with
platforms chosen in the console. Adding keys is a Run 0-style hotspot
(the YAML feature count, plan rows in `dev.tfvars`/`prod.tfvars`, the
console checkboxes) batched at the Run 3 cut.

IAM (new rows, call out) **[NEEDS YOUR OK]**: per platform one app
secret `${prefix}ads/<platform>-app` (value by hand); the existing
meta-ads roles gain `GetSecretValue` on them and Secrets Manager CRUD on
`booqy/<env>/ads/*`. Second row: decision 4 replaces the Meta-only spend
metric with `Booqy/Ads PlatformSpendSek` per platform, so the
`meta-ads-jobs` role's `cloudwatch:PutMetricData` condition
(`cloudwatch:namespace`, `meta-ads/main.tf:184`) changes from
`Booqy/MetaAds` to `Booqy/Ads`, together with the spend alarm's
`namespace` (`meta-ads/main.tf:524`) in the same change. Nothing else
changes. Both rows are listed in PIPELINE.md "Needs owner (spec change
2026-11-04)" and go into the Run 2 infra PR for approval.

## Run plan

No run of its own. **A2 (Run 2):** the port, `MetaAdPlatform`, the
publish workflow on the port, spend confirmation (A11'), schedules
(A22-A24, sweep), first-time guide, daily view (A25), plain tracking,
the Konton card with the Meta guide, brand and usability review.
Meta-only in behaviour, so it is verifiable against the Meta simulator
and ships dark (every key stays as today). **A3 Google Ads and A4
TikTok (Run 3):** adapters, simulators, guides, their entitlement keys;
real adapters are `unverified` in STATUS.md until the approvals land,
like every other real client. If Run 2 cannot fit A2 next to G (which
shares A's Meta connection), A2 slides to Run 3 before A3; it never
blocks D-H, K or L.

## External dependencies and human actions

- Meta: as ADR-A (open).
- Google: Booqy manager account, developer token, Explorer then Basic
  access application, **brand verification**, OAuth consent-screen
  verification; a test manager account with test client accounts for
  the Run 3 builder.
- TikTok: developer app, app review and data-security compliance; a
  sandbox advertiser account.
- Lawyer: alcohol rules per platform before any platform allows it;
  marknadsföringslagen for automated recurring ads (the owner remains
  the advertiser and approved the template); DSA fields on Google
  (EU transparency fields) and TikTok.
- Accountant: none (media spend never passes through Booqy).

## Test plan

Every new route: happy path, validation error, wrong role (staff 403
`owner_only`, or per the flagged decision), foreign tenant 404,
entitlement off 403, idempotent retry. Plus: the port contract test runs
against every simulator (`capabilities()` consistent with what
`create_campaign` accepts); publish workflow unchanged for Meta
(existing tests pass on the adapter); `total_mismatch` refuses activate
and schedule creation; schedule limits (5th schedule 409, 13th run
refused, 6-month end); a run skipped at the cap, at kill switch and at
`needs_reauth`, stopped after 3 skips, idempotent by run day, resumable
after a failure mid-run; monthly spend summed across platforms hits 80 %
and 100 % once; daily view lists exactly the running campaigns and
every attention item with one action; grep test: no pixel, no
conversions API, no third-party SDK script in admin; two-tenant
isolation for every new key; UI at mobile, tablet, desktop, light and
dark; the first-time-owner walkthrough recorded by the brand guardian.

## Alternatives considered

- **Generic routes and renaming `meta-ads` to `ads` now:** cleanest
  naming, but it rewrites Run 1 code and the contract on `dev` for no
  behaviour change. Rejected; the port is added under the existing ids.
- **One adapter per platform in its own feature (ids `google-ads`,
  `tiktok-ads`) with its own table and Lambdas:** isolates ownership,
  but the wizard, caps, schedules and daily view would be built three
  times. Rejected for one feature with adapters.
- **Platform-side scheduling (Meta/Google ad scheduling) instead of
  Booqy schedules:** the platforms schedule delivery hours, not a new
  campaign per week with its own total; Booqy's schedule is what gives
  the restaurant a bounded, confirmed total per run. Rejected.
- **Daily budgets edited in place to "change spend":** Google and
  TikTok allow it, Meta does too, but a mid-flight change would make the
  confirmed total wrong; pause plus a new campaign keeps the
  confirmation honest. Chosen for v1, flagged.

## Open questions

1. Money screens (decision 8) - owner to pick (a), (b) or (c).
2. Google account model: manager link or per-user OAuth (decision 2).
3. TikTok creative: image-to-video or uploaded video only (decision 2).
4. Entitlement keys: per platform or one `ads` key (contract sketch).
5. Schedule runs: auto-activate or confirm each run (decision 5).
6. Which of Snapchat and Pinterest, if any, after A4.
