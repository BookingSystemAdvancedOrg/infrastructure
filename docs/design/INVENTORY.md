# Brand inventory (Run 0, step 8b)

Every visual effect, component and bar-like element in the Booqy frontends
and emails on 2026-11-01, with the file it lives in and whether it is a
duplicate. Paths are relative to the repo named in each heading. "Dup" names
the copies of the same thing; **brand** names what replaces it in
`customer-front-end/packages/brand` (`@booqy/brand`, see DESIGN.md). Run 3
moves each row onto the package and deletes the old code.

Repos: **admin** = `admin-front-end/src`, **console** = `booqy-console/web/src`,
**guest** = `customer-front-end/src`, **kit** =
`customer-front-end/packages/site-kit/src`, **site** = `booqy-website/site`,
**app** = `application`, **infra** = `infrastructure`.

Brand-lint report-only counts on the same date (`node
customer-front-end/packages/brand/scripts/brand-lint.mjs <paths>`):

| App | Files | Total | colour | spacing | radius | duration | keyframes | bar | duplicate |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| admin-front-end/src | 175 | 1463 | 363 | 782 | 25 | 98 | 19 | 153 | 23 |
| booqy-console/web/src | 50 | 656 | 277 | 238 | 12 | 63 | 18 | 28 | 20 |
| customer-front-end/src | 11 | 248 | 138 | 88 | 2 | 16 | 0 | 3 | 1 |
| customer-front-end/packages/site-kit/src | 72 | 861 | 242 | 432 | 21 | 77 | 26 | 57 | 6 |
| booqy-website/site | 15 | 981 | 282 | 405 | 44 | 161 | 86 | 3 | 0 |
| application/shared | 55 | 62 | 62 | 0 | 0 | 0 | 0 | 0 | 0 |
| application/functions | 55 | 16 | 16 | 0 | 0 | 0 | 0 | 0 | 0 |
| booqy-console/api/src | 18 | 19 | 19 | 0 | 0 | 0 | 0 | 0 | 0 |
| infrastructure/compute/lambda | 25 | 9 | 9 | 0 | 0 | 0 | 0 | 0 | 0 |

Counted after the pilots (admin and console lost their busy-bar rules and keyframes). The
lint is a heuristic: it over-counts (every hex in a Python email, every raw
px) rather than miss; Run 3 drives each app to zero and then switches it to
blocking.

## 1. Tokens

### 1.1 Colour

The six browns (espresso `#1A120E`, walnut `#3A2418`, bronze `#6B4A2E`, tan
`#A88462`, sand `#D5C4AE`, graphite `#4A4A46`) plus linen `#F6F1EA` and white
are the same everywhere; the names and the semantic layer are not.

| Where | Defined in | Notes |
|---|---|---|
| admin | `index.css` `:root` (l. 62) and `[data-theme='dark']` (l. 141), glass block (l. 250+) | `--bg --surface --fill --ink --muted --border --accent* --on-accent --brand --ox* --on-ox* --slip --danger* --success* --warning* --purple* --tint-* --trend-* --scrim --glass --glass-hi --rim --wall-tint* --liquid-*`. Dark only under `[data-theme]` (light default). |
| console | `styles.css` l. 61 (old oxblood/paper set, still read by the layout) and l. 924 "glass room" (overrides it) | Two layers of the same tokens: `--ox-*`, `--paper*`, `--print*`, `--ink-red`, `--steel*`, `--notice-*`, `--glass`, `--lift`, `--hang`. **Dup** of admin with other names. |
| guest | `booqy-look.css` l. 79 | Admin's values copied, plus `--paper* --print* --steel*` aliases; **hard-codes `--accent: #1a120e`**, so the restaurant colour never shows (known gap, section 6 of DESIGN.md). |
| kit | `styles/theme.css` | Bongrail defaults, `--accent: var(--tenant-accent, #350001)`. Overridden by guest's `booqy-look.css`. |
| site | `assets/booqy.css` l. 64, l. 1303, l. 2928 ("glass room") | One look. `--paper-line` is tan here, sand in console, `#e3d6c4` in admin. `data-theme="dark"` is on every page but means the one light look. |
| emails | `app/shared/messages.py` (`#f4f2ee`, `_brand_color` default `#1f2a24`), `order_messages.py`, `catering_messages.py`, `card_messages.py`, `kassa_receipt.py`, `marketing.py`; console `api/src/app/mail.py` (`#f1eee6`, `#fbfaf6`, accent `#1a120e`); `infra/compute/lambda/demo-request`, `cognito-custom-message` | Inline hex, no shared source; transactional mails grey/green, the console newsletter paper/rail. **Dup x8.** |

Line colours disagree: `#e3d6c4` (admin, guest), `#d5c4ae` (console glass),
`#a88462` (site paper-line). Brand: `line` `#e3d6c4`, `line-strong` tan.

Status colours agree across admin, console and guest: danger `#9e1d26` /
dark `#ee8a90`, success `#2c6a3f` / `#7cc695`, warning `#8a5a00` / `#e0b35a`,
trend dark `#a3dcb4` / `#f6b0b5`. Notice tints only in console (`--notice-*`).

### 1.2 Type

Four families with one role each, the same in admin, console, guest and site:
Bricolage Grotesque (display, figures), Athelas/Newsreader (eyebrows), Plus
Jakarta Sans (UI), Martian Mono (printed things). Font files are copied into
each app's `assets/fonts` (admin, console, guest, site: **dup x4**); kit's
default is Archivo. Sizes: admin 15 px base, console 15 px, site a clamp
scale `--text-xs`..`--text-5xl`. Brand: font tokens plus a fixed UI scale;
the font files stay per app until Run 3.

### 1.3 Spacing

No scale anywhere: raw px in every app (spacing is the largest lint count).
Brand adds `--bq-space-0..16` (4 px steps).

### 1.4 Radii

The corner scale was just unified (commit "One corner scale in every app"):
panels 28, cards and dialogs 22, inner boxes 14, pills 9999, round 50 %.
Defined as `--r-md/--r-lg/--r-panel/--r-pill` in admin `index.css`, console
`styles.css` l. 944, guest `booqy-look.css`, site `booqy.css` l. 2941
(**dup x4**). Emails still use 10 px. Brand: `--bq-radius-inner/card/panel/pill/round`.

### 1.5 Shadows and glass

`--shadow`, `--shadow-lg` (admin, guest), `--lift`, `--lift-sm`, `--hang`
(console, site), `--rim` (all four), `--card-shadow*`, `--plate-shadow`,
`--rail-shadow` (guest). **Dup x4** with two naming schemes. Brand:
`--bq-shadow-sm/md/lg/pill/rim`.

### 1.6 Motion tokens

`--ease` `cubic-bezier(0.16,1,0.3,1)` (admin, console, guest), `--spring`
(admin, same value), `--ease-out/--ease-expo/--ease-std/--ease-emph` (site),
glide `cubic-bezier(0.22,1,0.36,1)` and theme sweep `(0.65,0,0.35,1)` inline
in TS. Durations are inline everywhere. Brand: `--bq-ease-*`, `--bq-duration-*`.

## 2. Effects

| Effect | Variants (file) | Dup | Brand |
|---|---|---|---|
| Glass and refraction (SVG `booqy-glass`) | admin `shared/glassFilter.ts`; console `glassFilter.ts`; site `assets/booqy.js` l. 664; glass CSS in admin `brand.css`, console `styles.css` l. 924+, guest `booqy-look.css`, site `booqy.css` l. 2912+ | x3 JS, x4 CSS | `installGlassFilter`, `.bq-glass`, Card `surface="glass"` |
| Liquid fill (tiles) | admin `shared/motion/liquid.ts`, `useLiquidFill.ts`, `StatTile.tsx`; re-exported by `features/oversikt/liquid.ts` | x1 (+re-export) | `Liquid`, `pourLiquid`, `useLiquidFill`, `StatTile` |
| Sidebar pour | admin `AdminLayout.tsx` l. 149/189 (`sidebarShouldPour`, `.admin-sidebar-liquid`) on `useLiquidFill` | none | `useLiquidFill` (pour rule stays in admin's `MotionScope`) |
| Once-per-login gate | admin `shared/motion/MotionScope.tsx` (`claimReveal`, `claimNumberReveal`) | none | app policy, passed as `reveal`/`enabled` |
| Count-up | admin `shared/motion/countUp.ts`, `Num.tsx` (re-export `features/oversikt/countUp.ts`); console `components/motion.tsx` (`CountUp`, `useSpring`, `easeOutExpo`) | x2 | `countUp`, `CountUp`, `easeOutExpo` |
| Trend pop | admin `shared/motion/useTrendPop.ts`, `trend.css` (`trend-pop`); console `components/motion.tsx` (`useTrendPop`), `styles.css` (`trend-pop`) | x2 | not yet (Run 3: StatTile `trend` colours only) |
| Skeletons | admin `shared/Skeleton.tsx` + `skeleton.css` (11 parts); console `components/Skeleton.tsx` + `styles.css` l. 1562 (9 parts); kit `shared/Skeleton.tsx` + `components.css` (5 parts) | x3 | `Skeleton`, `SkelBlock`, `SkelLines`, `SkelCard` |
| Receipt print (loading) | admin `shared/Loading.tsx` + `loading.css` (printer, slip, torn edge); console `components/ui.tsx` `Printing` + `styles.css` l. 286 (`print-line`); kit `SiteProvider.tsx` boot `.printing` + `world.css` (`print-line`); kit `styles/payment.css` (`pay-print-out`); site `booqy.css` (`printout`, `feed-x`) | x4 | `Printing` (`inline`, `block`, `screen`) |
| Busy store and bar | admin `shared/motion/busy.ts` + `BusyBar.tsx`; console `busy.ts` + `components/BusyBar.tsx` | x2 | `busyStart/End/withBusy/useBusy` + `Bar variant="busy"` (**pilot done in both**) |
| Theme switch and sweep | admin `shared/theme.ts`, `ThemeToggle.tsx/.css`, `public/theme.v2.js`; console `theme.ts`, `components/ThemeToggle.tsx`; kit `shared/theme.ts`, `ThemeToggle.tsx`, guest `public/theme.v2.js` | x3 | `configureTheme`, `setTheme`, `switchTheme`, `useTheme` |
| Glide pill | admin `shared/glide.ts` (13 selector groups) + `brand.css` l. 1344; console `glide.ts`; guest `shared/glide.ts` (`.chip-rail`); site `booqy.js` l. 287 (`.lnav` pill) | x4 | `installGlide` with `data-bq-glide`; Bar `tab` and `nav` |
| Press ripple and squeeze | admin `shared/press.ts` + `brand.css` (`press-dot`, `press-signal`); console `press.ts` + `styles.css`; kit `shared/sound.ts` + `world.css`; site `booqy.js` l. 681 + `booqy.css` l. 2835 | x4 | `installPress`, `.bq-ripple` |
| Click sound (pre-rendered buffer, Safari wake-on-release) | admin `shared/press.ts`; console `press.ts`; kit `shared/sound.ts`; site `booqy.js` | x4 (identical engine, different selectors) | `playClick`, `installSoundUnlock`, `setSound*`; buffer kept |
| Sound and volume controls | admin `SoundToggle.tsx`, `SoundVolume.tsx`; console `components/SoundToggle.tsx`, `SoundVolume.tsx`; kit `SoundToggle.tsx`; site footer "Ljud på/av" | x4 | hooks `useSound`, `useSoundVolume` (controls stay per app) |
| Card drop-in / page-in | console `styles.css` (`drop`, `page-in`, `dot-in`, `area-in`); kit `world.css` (`drop`, `page-in`, `step-in`); site (`drop`, `step-in`, `arrive`) | x3 | Modal/Toast `bq-modal-in` only; others stay until Run 3 |
| Save feedback | console `components/save.tsx` (`save-flash`, `save-pop`, `save-pulse`, `CheckMark`) | none | not yet |
| Confetti | kit `shared/Celebrate.tsx` (`confetti-fall`); site `booqy.css` | x2 | not yet (one-off delight, stays) |
| Site-only scenes | site `booqy.css` (`g-*`, `pb-*`, `pz-*` device and story animations, 60+ keyframes), `[data-tilt]`, `[data-reveal]`, before/after slider | none | stay on booqy.se (marketing scenes, not UI) |

## 3. Components

| Component | Variants (file) | Dup | Brand |
|---|---|---|---|
| Button | admin `.btn`, `.btn.primary/.outline/.danger-outline` (`admin.css`, `brand.css`); console `.btn--primary/--danger/--ghost/--small` (`styles.css` l. 296); kit `.btn`, `.btn.primary`, `.btn-primary`, `.btn-secondary` (`components.css` l. 398, l. 1183); guest overrides in `booqy-look.css` l. 472; console `components/save.tsx` `SaveButton`, `RefreshButton` | x4 | `Button`, `LinkButton` (**guest pilot: Kontakt "Skicka"**) |
| Card | console `components/ui.tsx` `Card`; admin `.admin-card`; kit tickets (`world.css`) | x3 | `Card` (`paper`, `glass`, `receipt`) |
| Modal | console `components/ui.tsx` `Modal` (div, Esc listener); admin per feature (`LogoutConfirm`, `OpeningHoursModal`-style); kit `shared/OpeningHoursModal.tsx` | x3+ | `Modal` on native `<dialog>` |
| Field | console `components/ui.tsx` `Field`; admin per page labels; kit form CSS; guest `site.css` `.contact-form-field` | x3 | `Field`, `Input` |
| Select | admin `shared/select.css` (`appearance: base-select`); console `--select-chevron` data URI; guest `site.css` select | x3 | `Select` (native) |
| Notice / inline message | console `ui.tsx` `Notice`, `ErrorNotice`; admin `.notice`; guest `.notice` | x3 | Bar `banner` |
| Status chip | console `ui.tsx` `Status` | none | `Chip` |
| Stat tile / KPI | admin `shared/motion/StatTile.tsx` (re-export `features/oversikt/StatTile.tsx`), `oversikt/MonthCard.tsx`; console `.kpi`, `.kpi--hero` (`styles.css` l. 627) | x2 | `StatTile` |
| Charts | admin `features/statistik/charts.tsx` (`ColumnChart`, `BarChart`, `Ring`, `Heatmap`, `Sparkline`, `Delta`, `ChartTable`); console `components/charts.tsx` (`BarLineChart`, `LineChart`, `HBarChart`), `Ring.tsx`; tooltips admin `ChartTip.tsx` + `chartTipState.ts`, console `ChartTip.tsx` + `chartTipState.ts` | x2 each | `BarChart`, `ColumnChart` (chart Bars), meter `ring`; line, heatmap and tooltip not yet |
| Trend badge | admin `shared/TrendBadge.tsx`, `trend.ts`; console `trend.ts`, `motion.tsx` `Delta` | x2 | StatTile `trend`, `delta` |
| Date and phone inputs | admin `DateInput.tsx`, `PhoneInput.tsx`; console `PhoneInput.tsx`; kit `DateInput.tsx`, `PhoneInput.tsx` | x3 | not yet |
| Logos | admin `BrandMark.tsx`; console `components/Logo.tsx`; guest `shared/BooqyWordmark.tsx`; site `assets/booqy-logo.png` | x4 | stay per app (CLAUDE.md); partner logos never recoloured |
| Plate, floor plans | kit `Plate.tsx`, floor SVG/3D; admin `layout-editor` | none | stay |

## 4. Every bar-like element

| Kind | Element (file) | Dup | Bar variant |
|---|---|---|---|
| Busy / loading strip | admin `BusyBar` (`.busy-bar`); console `BusyBar` (`.busy-bar`) | x2 | `busy` (**both migrated**) |
| Progress | site `.show-prog` hairline (`booqy.js` l. 136, `booqy.css` l. 1893) (**migrated**); site "Så funkar det" tab pill `--p`; kit `.hold-bar` (`BokaBordPage.tsx` l. 102, `world.css`); kit `.order-steps` / `FlowSteps.tsx`; admin `.sk-progress` (statistik), `.printer-steps` (`printer.css`); site `.mini-steps`, `.g-steps` | x7 | `progress` |
| Chart bars | admin `.sk-bar` (`statistik.css`, `charts.tsx` l. 168, 278); console `.chart__bar` (`charts.tsx`), `.web-bar` (`WebsitePage.css`); site `.fp-bar`, drum-fill bars (`booqy.js` l. 484) | x4 | `chart` (BarChart, ColumnChart) |
| Meters and rings | admin `.sk-ring` (statistik `Ring`), `.side-ring` (layout editor); console `Ring.tsx` (`.ring__seg`); site `.term-ring`, `.fp-ring`, `.pb-ring`; sound volume rails (admin `SoundVolume`, console `SoundVolume`) | x5 | `meter` (`line`, `ring`) |
| Tab bars / segmented | admin `.settings-tabs`, `.mk-tabs`, `.mk-segment`, `.sk-chips`, `.segmented`, `.kassa-switch`, `.kassa-cats`, `.kassa-chips`, `.floor-tabs`, `.view-toggle`, `.shape-toggle`, `.floor-list`, `.pay-mode` (all glide groups); console `.tabs` (`styles.css` l. 335), `.web-tabs`; kit `.floor-view-toggle`, `.offer-tab`; guest `.chip-rail`; site `.scene-tabs`, `.g-switch`, `.ph-tabs` | x20+ | `tab` (`track`, `bare`) |
| Top and nav bars | admin `.admin-topbar` (`AdminTopbar.tsx`), `.admin-nav*`; console `.topbar`, `.topbar__nav`; guest `.site-header-nav` (`CustomerLayout.tsx`); kit `.category-sidebar` (`CategoryNav.tsx`); site sticky header, `.lnav` chapter bar, `.subnav`, `.r-nav`, "Tjänster" menu | x8 | `nav` |
| Sidebar | admin `.admin-sidebar` (with liquid pour); site none; console none | none | `nav vertical` + `useLiquidFill` |
| Toolbars and action bars | console `.submit-bar` (12 rules), `.toolbar`, `.finance-toolbar`, `.web-toolbar`; admin `.mk-toolbar`, `.mk-bar`, `.editor-toolbar`, `.sk-filterbar`, `.kassa-bar`, `.kassa-print-bar`; kit `.checkout-bar`, `.order-mobile-bar` (also in guest `site.css`, `booqy-look.css`) | x12 | `action` |
| Status bars | admin `.editor-statusbar` (layout editor) | none | `action` (status slot) |
| Banners | admin `.orders-banner` (bestallningar), `.dpa-banner` (DPA prompt, seen on Översikt), `.layout-viewmode-banner` (layout editor and cateringkalkyl); kit `.hold-banner`; console `Notice` | x5 | `banner` |
| Toasts | none today (saves flash in place); console `saved-stamp` | none | `banner` in `Toaster` |

## 5. Emails

All inline-styled Python strings with a text twin; no shared values.

| Template | File | Look |
|---|---|---|
| Booking guest/staff, SMS | `app/shared/messages.py` (`guest_email`, `staff_email`, `guest_sms`) | 560 px, `#f4f2ee`, white card radius 10, tenant colour (`_brand_color`, default `#1f2a24`) top border and CTA, system fonts |
| Order, catering, card, Kassa receipt | `app/shared/order_messages.py`, `catering_messages.py`, `card_messages.py`, `kassa_receipt.py` | same shape as messages.py (**dup x4**) |
| Marketing campaigns | `app/shared/marketing.py` `render_email` (editor `admin/features/marknadsforing/TemplateEditor.tsx`) | 600 px, menu images, template colour theme |
| Operator newsletter | `booqy-console/api/src/app/mail.py` `render_html` | 600 px table, steel rail, `#fbfaf6` paper, torn edge, accent `#1a120e` (the only Booqy-looking mail, old palette) |
| Demo request | `infra/compute/lambda/demo-request/src/handler.py` `build_email` | own inline look |
| Password reset, invites | `infra/compute/lambda/cognito-custom-message/src/handler.py`; `infra/storage/cognito/variables.tf`, `cognito-platform/main.tf` | plain |

Brand: `@booqy/brand/email-tokens.json` and `dist/booqy_brand_tokens.py`
(flat light values; ADR-BRAND-sharing.md). Guest mails keep the restaurant
colour (restaurant theme), staff and operator mails use Booqy's.

## 6. Duplicates to delete in Run 3 (summary)

1. Effect engines copied 3-4 times: press + sound, glide, glass filter, theme,
   busy, count-up, skeletons, receipt print.
2. Token sets copied 4 times under two naming schemes, plus 8 email palettes.
3. BusyBar x2 (now thin wrappers over Bar), Ring x2, ChartTip x2, Skeleton x3,
   PhoneInput x3, DateInput x2, SoundToggle x3, ThemeToggle x3, Printing/Loading x4.
4. 20+ tab/segmented groups styled by one global glide stylesheet per app.
5. Font files x4.
