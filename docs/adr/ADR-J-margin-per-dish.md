# ADR-J: Margin per dish

**Status:** Proposed
**Date:** 2026-11-01
**Deciders:** Owner (product), orchestrator
**Run:** built in Run 3

## Context

Statistik already shows best and worst dishes: the nightly `insights-rollup`
writes per location and day `d: {"<menuItemId>": {n: name, q: {hour: qty},
r: {hour: öre incl. VAT}}}` (`shared/insights.py` `_order`), `summarize`
turns it into `dishes[]`, and `without_money` strips `revenue` for staff
(BR-REST-084: staff see no amounts, removed on the server). The "Att göra"
signals (BR-REST-081) are computed in the admin app
(`features/statistik/insights.ts` `signals`). Menu items have a price incl.
VAT and an `alcohol` flag (VAT 25/12 % via `shared/orders.vat_rate`) but no
cost. The public `get-menu` returns menu items to guests, so a cost field on
the menu item would risk leaking to the site.

## Decision

1. **Costs live in their own table, not on the menu item**, so no public
   menu reader can ever return them.
2. **Manual entry, effective-dated.** The owner enters the ingredient cost
   per portion in kronor and öre, excluding VAT, with a "gäller från" date
   (default today). A change is a new row; old periods keep the old cost.
3. **Margin is computed at read time in `insights`**, from the existing
   day rows (`d.q`, `d.r`) and the cost valid on each day:
   `net = r / (1 + vat)`, `cost = q * costOre`, `margin = net - cost`,
   `marginPct = margin / net`. No rollup change, no rebuild; a corrected
   cost shows at once. Dishes without a cost get `margin: null` and count in
   `missingCost`.
4. **Hidden from staff.** `margin`, `marginPct`, `cost` and `missingCost` are
   added to the money fields that `without_money` removes, so the staff
   response has no margin data at all (a percentage reveals amounts too).
   Cost routes are owner only.
5. **Att göra** gains two signals in `insights.ts`, using only server fields
   (so they disappear for staff automatically): "Låg marginal" (marginPct
   under the owner's target, default 65 %, among dishes with at least 10
   sold in the period) and "Kostnad saknas" (top sellers without a cost).
6. **Scope v1: online orders only**, because the day rows' `d` only covers
   orders today. Kassa sales by dish are not in insights; the chart says so
   ("Gäller onlinebeställningar"). Adding Kassa lines to the rollup is an
   open question that would widen BR-REST-082 for all dish charts.

## Data model

Table `<prefix>dish-margin` (PAY_PER_REQUEST, PITR, deletion protection in
prod; no TTL, costs are not personal data).

| PK | SK | Item |
|---|---|---|
| `LOCATION#<l>` | `COST#<menuItemId>#<yyyy-mm-dd>` | `tenantId`, `locationId`, `menuItemId`, `validFrom`, `costOre` (0-1,000,000, integer), `setBy`, `setAt` |
| `LOCATION#<l>` | `SETTINGS` | `targetMarginPct` (1-95, default 65), `version` |

Reads: one Query `PK=LOCATION#<l>`, `begins_with(SK, COST#)` per location
(hundreds of rows at most), then pick per dish and day the latest
`validFrom <= day`. No GSI. Writing the same item, date and cost twice is a
plain overwrite.

## API routes

All JWT, **owner only**. `menuItemId` must exist in the location's menu.

| # | Method | Path | Request -> response |
|---|---|---|---|
| 1 | GET | `/locations/{locationId}/dish-costs` | -> `{settings, dishes[{menuItemId, name, priceOre, vatRate, current?{costOre, validFrom}, history[]}]}` |
| 2 | PUT | `/locations/{locationId}/dish-costs/{menuItemId}` | `{costOre, validFrom?}` -> the dish entry |
| 3 | PUT | `/locations/{locationId}/dish-costs/settings` | `{targetMarginPct, version}` -> settings |
| 4 | GET | `/locations/{locationId}/insights` (existing, extended) | `dishes[]` gain `cost`, `margin`, `marginPct`; summary gains `missingCost`, `targetMarginPct`; all removed for staff |

Errors: 400 `invalid_cost`, `invalid_valid_from` (more than 2 years back or
in the future), `unsupported fields`; 403 `feature_not_in_plan`,
`owner_only`; 404 foreign location or unknown/foreign menu item; 409
`changed_retry` (settings).

Idempotency: route 2 is a deterministic key per item and date (retry
overwrites with the same values, 200); route 3 is conditional on `version`.
Route 4 adds margin fields only when `dishMargin` is on; off means the
existing response is unchanged (not refused, since insights itself is not
this feature).

## Events

Bus `<prefix>booqy-events`, source `booqy.dish-margin`.

| detail-type | detail |
|---|---|
| `DishMargin.CostSet` | `tenantId`, `occurredAt`, `version: 1`, `locationId`, `menuItemId`, `validFrom` (no amount) |

No consumers planned.

## Terraform modules

- `infrastructure/dish-margin/`: table, Lambda `dish-margin` (routes 1-3),
  role (its table CRUD, menu table read, tenant-context), Errors alarm.
- Root `dish-margin.tf`; routes `network/api-gateway/dish-margin-routes.tf`.
- **IAM change to existing roles (call out):** `insights` and
  `tenant-purge` get `lambda:InvokeFunction` on `dish-margin:live` only
  (hooks `insights.dishCosts`, `tenant.purge`); no table access on insights.
  Run 0 builds the insights call site, the stripped fields and the
  `shared/dish_margin.py` stub; J fills `apply()` and answers the hook.
- Wiring through the module's `wiring` output (ECR repo by Run 0).

## Entitlement name

`dishMargin`. Off -> 403 `feature_not_in_plan` on routes 1-3; route 4 omits
the margin fields.

## Plan availability (target)

growth. Run 0 ships `false` in every plan.

## UI placement

- Admin, group `restaurangen`, `/meny`: in the dish editor, owner only,
  field "Råvarukostnad per portion (exkl. moms)" with "Gäller från" and the
  live margin ("Marginal 68 %"). Staff never see the field.
- Admin, group `overblick`, `/statistik`: in the dishes section of "Varför",
  a "Marginal" chart (margin per dish, sortable, table view and CSV like the
  other charts, "Gör så här" line), a target line at `targetMarginPct`, and
  the two Att göra signals. Hidden entirely for staff (no empty chart).
- Target margin setting: on the same chart ("Mål för marginal").
- Charts use the brand Bar family (chart variant) per RULES.md.
- Console: only the generic feature checkbox.
- Storage registry: no new keys.

## External dependencies

None. Nothing mocked, no approval needed.

## Privacy and GDPR

No personal data (costs and aggregates). `setBy` is the owner's `sub`,
legal basis contract. Tenant-purge deletes the rows. Costs are business
secrets: never in public responses, logs or events.

## Swedish legal notes (human check)

- None specific. Margins are management figures, not bookkeeping; they are
  never exported to SIE or posted (ADR-I). Confirm the "exkl. moms" wording
  with the accountant reviewer.

## Test plan

Two-tenant fixtures, `mock_aws()`. Each route: happy path, validation error,
wrong role, foreign tenant 404, entitlement off, idempotent retry.

| # | Validation | Wrong role (staff) | Foreign 404 | Off | Retry |
|---|---|---|---|---|---|
| 1 | n/a | 403 `owner_only` | LOC_B 404 | 403 | n/a |
| 2 | negative cost; future validFrom | 403 | LOC_B; menu item of B under LOC_A | 403 | same body twice -> one row, same response |
| 3 | 0 or 96 % | 403 | LOC_B | 403 | stale version 409 |
| 4 | existing insights tests unchanged | staff response has no `cost`, `margin`, `marginPct`, `missingCost` (asserted on the raw body) | LOC_B 404 (existing) | fields absent, rest identical | n/a |

Plus: cost change mid-period uses each day's cost; VAT 12 % food and 25 %
alcohol give the right net; dish without cost -> `margin: null` and counted;
zero revenue day does not divide by zero; `get-menu` (public) response has no
cost field (regression test); admin `signals` unit tests for both new
signals and none for staff data; UI light and dark, mobile, tablet,
desktop.

## Alternatives considered

- **`cost` on the menu item** (`manage-menu` `_EDITABLE_FIELDS`): one less
  table, but every menu reader (public `get-menu`, site-config, caches)
  would need to strip it, and staff can edit dishes. Rejected.
- **Store margin in the nightly rollup**: a cost correction would need a
  rebuild of history; read-time computation is cheap at this size.
- **Recipes and ingredient lists**: real food costing, but a large feature
  (units, suppliers, waste). Out of scope; the manual per-portion cost is the
  smallest useful version.

## Open questions

1. Include Kassa sales in dish figures (rollup change for all dish charts)?
2. Default target margin: 65 % is a guess; owner to confirm.
3. Should staff with "operations" access see a margin-free "Kostnad saknas"
   reminder? v1: no.
