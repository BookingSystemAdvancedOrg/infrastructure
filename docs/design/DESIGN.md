# Booqy design system (`@booqy/brand`)

The one source for how Booqy looks, moves and sounds in admin, the console,
the guest sites and booqy.se. Code: `customer-front-end/packages/brand`.
How repos get it: `docs/adr/ADR-BRAND-sharing.md`. What exists today and what
it replaces: `docs/design/INVENTORY.md`.

Rules for feature code (RULES.md, Brand): use tokens, effects and components
from this catalogue only; no hard-coded colours, spacing, radii, shadows,
durations or keyframes; every bar-like element is a `Bar`; a missing variant
is requested from the brand guardian, never hand-rolled. `brand-lint` blocks
new code paths listed in OWNERSHIP.md.

## 1. Setup per app

```tsx
// main.tsx, once
import '@booqy/brand/styles.css'
import { configureTheme, installGlassFilter, installPress } from '@booqy/brand'

configureTheme({ defaultTheme: 'light' }) // admin; console and guest: 'system'
installPress()        // click sound + squeeze + ripple
installGlassFilter()  // refraction on Chromium
```

Each app keeps its own pre-paint boot script (`public/theme.v2.js`) that sets
`<html data-theme>` from `booqy-theme`. Storage keys used by the package
(`booqy-theme`, `booqy-sound`, `booqy-sound-volume`) already exist in every
app's storage registry; the package adds none.

Every class is `bq-*` and every variable `--bq-*`, so the package sits next
to an app's own CSS without collisions during the Run 3 migration.

## 2. Tokens

Single source: `packages/brand/tokens.json`. `npm run tokens` generates
`src/generated/tokens.css` (light, dark, restaurant), `tokens.light.css`
(booqy.se), `tokens.ts`, `email-tokens.json` and `booqy_brand_tokens.py`. A
test fails when the generated files drift, and another checks every text pair
the components use at 4.5:1 and every bar fill at 3:1 in both modes.

| Group | Variables | Values |
|---|---|---|
| Palette | `--bq-espresso walnut bronze tan sand graphite linen white wine roast` | `#1a120e #3a2418 #6b4a2e #a88462 #d5c4ae #4a4a46 #f6f1ea #fff #350001 #2a1d16` |
| Surfaces | `--bq-bg surface surface-2 glass glass-hi track scrim` | light: linen, white, linen, white 62/74/90 %; dark: espresso, roast, walnut, espresso 70/80 % |
| Text | `--bq-ink muted accent-ink` | light espresso, graphite, bronze; dark linen, sand, sand |
| Accent | `--bq-accent accent-hover on-accent brand on-brand focus` | Booqy: espresso pill with white text (dark: linen pill, espresso text); wine `#350001` is `--bq-brand` |
| Lines | `--bq-line line-strong hover` | `#e3d6c4` / tan; dark `#4a3326` / bronze |
| Status | `--bq-danger success warning`, `--bq-{info,success,warning,danger}-{bg,ink}` | the admin/console values; banner pairs from console's notices |
| Effects | `--bq-busy busy-glow busy-wave ripple ripple-ring skeleton sheen liquid liquid-alpha chart-1..4` | see tokens.json |
| Type | `--bq-font-sans display serif mono`, `--bq-text-xs..4xl` | Plus Jakarta Sans (UI), Bricolage Grotesque (headings, figures), Athelas/Newsreader (eyebrows), Martian Mono (printed things); 12 13 15 17 20 24 32 46 px |
| Space | `--bq-space-0..16` | 0 4 8 12 16 20 24 32 40 48 64 px |
| Radius | `--bq-radius-inner card panel pill round` | 14, 22, 28, 9999, 50 % (the unified corner scale) |
| Shadow | `--bq-shadow-sm md lg pill rim` | per mode |
| Motion | `--bq-duration-press fast base slow bar glide drop theme ripple done count fill print creep`, `--bq-ease-out glide std sweep creep` | 90 160 200 360 500 520 640 700 820 900 1100 1500 2600 9000 ms |
| Layers | `--bq-z-bar modal toast ripple`, `--bq-bar-hairline thin regular` | 30 100 150 200; 1 4 8 px |

Fonts: the package names the families; each app still ships its font files
(INVENTORY 1.2) until Run 3 moves them into the package.

## 3. Theming model

One set of components and effects, two themes:

- **Booqy theme** (admin, console, booqy.se): the browns, glass and wine red
  above. `data-theme` on `<html>` switches light and dark; with no attribute
  the system decides (`prefers-color-scheme`). booqy.se has one look: it
  loads `brand-static-<v>.css`, built from the light tokens only, so its
  permanent `data-theme="dark"` changes nothing.
- **Restaurant theme** (guest sites): `data-bq-theme="restaurant"` on
  `<html>` (or a container) maps `--bq-accent`, `--bq-accent-hover`,
  `--bq-on-accent`, `--bq-accent-ink` and the sans/display fonts to the
  `--tenant-*` variables. site-kit's `SiteProvider.applyBranding` already sets
  `--tenant-accent`, `--tenant-on-accent`, `--tenant-accent-ink` and their
  `-dark` twins from `branding.primaryColor`, nudged by the existing helpers
  `accentPair`, `textOn`, `deepenForLight` and `liftForDark`, so every pair
  reaches 4.5:1 in both modes (BR-NFR-034). Without a restaurant colour the
  Booqy values remain. Optional `--tenant-font-sans` / `--tenant-font-display`
  take the restaurant's fonts (site-config has no font field yet; Run 1's
  site builder adds it). The logo stays the app's (`CustomerLayout`).

**Known gap (Run 3):** `customer-front-end/src/booqy-look.css` hard-codes
`--accent: #1a120e` (and the pill gradient), so outside the pilot the
restaurant colour never shows on the guest site. Run 3 removes that override,
puts `data-bq-theme="restaurant"` on `<html>` and verifies with two tenants
with very different colours. Nothing else was changed now.

## 4. Effects catalogue

| Effect | API | Use it for | Duration / easing | Reduced motion |
|---|---|---|---|---|
| Glass, refraction | `installGlassFilter()`, `.bq-glass`, `Card surface="glass"` | panels on the room (sidebar, page panel, tiles) | static | same look; `prefers-reduced-transparency` or no backdrop-filter: solid surface |
| Liquid fill | `pourLiquid(host, canvas)`, `useLiquidFill`, `StatTile` | a key figure arriving; admin's sidebar pour once per login | fill 1500 ms ease-out cubic, stagger 140 ms, settles by spring physics | full at once (`.bq-liquid--full`) |
| Count-up | `countUp(el, text)`, `<CountUp>` | every figure on first show and on change | 1100 ms easeOutExpo, last frame = exact text | text at once |
| Skeleton | `<Skeleton><SkelCard/></Skeleton>` | page and card loading where the layout is known | breathe 1.8 s, sheen 2.6 s | still blocks |
| Receipt print | `<Printing variant>` | loading without a known layout; inline "Hämtar…" | 2.6 s loop, ease-out | still slip |
| Busy | `busyStart/busyEnd/withBusy`, `useBusy`, `<Bar variant="busy">` | every save, publish, send (the busy bar) | creep 9 s `ease-creep`, wave 1.1 s linear, done 900 ms | static 70 % strip |
| Theme sweep | `switchTheme(theme, origin)`, `toggleTheme`, `useTheme` | the light/dark toggle | 700 ms circle, `ease-sweep` | instant |
| Glide pill | `installGlide()`, `data-bq-glide="track|bare"` (Bar tab and nav do it) | any one-of-many choice | 520 ms `ease-glide` | 160 ms linear |
| Press ripple, squeeze | `installPress(options)` | every press, all apps | squeeze 90 ms, ripple 420/820 ms | ripple off, short blink |
| Click sound | `playClick`, `setSound`, `setSoundVolume`, `useSound`, `useSoundVolume` | with press; settings toggle and volume | 80 ms pre-rendered AudioBuffer, one gain node | unchanged (sound is not motion) |
| Modal and toast entry | built in | dialogs, toasts | 640 / 360 ms ease-out | none |

The click sound must stay a pre-rendered buffer played through one gain
node: live oscillator or filter graphs were silent in Safari. The engine keeps
the Safari handling (new engine after 30 s idle, tab return or "interrupted";
a click pressed before the engine wakes plays on release).

## 5. Component catalogue

### 5.1 The Bar family

One component, `<Bar variant=...>`, root class `bq-bar bq-bar--<variant>`.

| Variant | Props | Semantics | Use for |
|---|---|---|---|
| `progress` | `value` 0..1, `label`, `valueText?`, `size` `hairline/thin/regular` | `role=progressbar`, valuenow, valuetext | steps, upload, hold timer, booqy.se tour |
| `busy` | `phase` `idle/busy/done`, `position` `sticky/fixed`, `busyLabel`, `doneLabel` | hidden when idle; polite status "Sparar…"/"Sparat" | the strip at the top of every app |
| `chart` | `value`, `max`, `label`, `valueText?`, `tone` `ink/tan/bronze/danger`, `orientation` | label and value are text | one bar in BarChart / ColumnChart |
| `meter` | `value`, `min`, `max`, `low`, `high`, `optimum`, `label`, `valueText?`, `shape` `line/ring` | `role=meter`; tone from the `<meter>` rules | occupancy, shares, rings |
| `tab` | `label`, `items`, `value`, `onChange`, `kind` `track/bare`, `panelId?` | `tablist`/`tab`, roving tabindex, arrows, Home, End | view switches, segmented choices, settings tabs |
| `nav` | `label`, `items {href,current}`, `orientation`, `linkAs?` (router Link) | `<nav>` + list, `aria-current="page"` | top nav, sidebar, chapter bar |
| `action` | `children`, `status?`, `sticky?`, `label?` | group when labelled | submit bar under forms, toolbars |
| `banner` | `tone` `info/success/warning/danger`, `action?`, `onDismiss?`, `dismissLabel` | status, or alert for danger | inline notices; every toast |

Need another bar? Ask the brand guardian for a variant; do not add classes.

### 5.2 Components

| Component | Props (main) | Notes |
|---|---|---|
| `Button`, `LinkButton` | `variant` `primary/secondary/ghost/danger`, `size` `md/sm`, `wide`, `busy`, `busyLabel` | pills; 44 px (md) / 32 px (sm) targets; busy = disabled + `aria-busy` |
| `Card` | `title`, `level`, `actions`, `surface` `paper/glass/receipt`, `tone` | receipt = white paper, tan rail, torn edge, mono, light print in both modes |
| `Modal` | `open`, `title`, `onClose`, `footer`, `closeLabel`, `size` | native `<dialog>` + `showModal`: focus trap, Esc, inert page, focus return |
| `Field`, `Input` | `label`, `hint`, `error`, `required` | wires `id`, `aria-describedby`, `aria-invalid`; focus the first invalid control after a refused save |
| `Select` | native `<select>` props | always native; `appearance: base-select` where supported |
| `Skeleton`, `SkelBlock`, `SkelLines`, `SkelCard` | `label` | one status region, blocks hidden from AT |
| `Toaster`, `toast()`, `dismissToast()` | `tone`, `timeoutMs` | banner Bars; pause on hover/focus; always dismissable |
| `StatTile` | `label`, `value`, `note`, `trend` `good/bad`, `delta`, `loading`, `index`, `reveal` | liquid fill + count-up |
| `Printing` | `label`, `variant` `inline/block/screen` | the receipt-print loader |
| `BarChart`, `ColumnChart` | `title`, `data[{key,label,value,valueText,tone}]`, `max`, `empty` | lists of chart Bars; values always as text |
| `CountUp` | `children` (formatted text), `reveal`, `delayMs` | |

Not in the package yet (INVENTORY 3): line/area charts, heatmap, chart
tooltip, trend pop, date and phone inputs, status chip, save stamp. Run 3
adds them before migrating the screens that use them.

Copy: components take every visible string as a prop with a Swedish default
("Stäng", "Hämtar", "Sparar…"); the console passes English.

## 6. Accessibility

WCAG 2.1 AA in both modes: text 4.5:1 and bar fills 3:1 (tested on the
tokens), visible focus ring (`--bq-focus`, 4 px), keyboard for tabs, nav,
dialogs and toasts, touch targets 44 px for primary controls, live regions for
busy and toasts, reduced motion and reduced transparency honoured. Colour is
never the only signal: chart and meter values are text.

## 7. Brand lint

`node packages/brand/scripts/brand-lint.mjs [paths] [--block <glob>] [--config file] [--json]`
(also the package bin `brand-lint`). Rules: colour, spacing, radius,
duration, keyframes, bar, duplicate. Report-only by default (counts per app,
exit 0); files matching a `--block` glob fail the run (exit 1) with
`file:line`. Default block list is empty; OWNERSHIP.md lists the globs for
each feature's new code. Report-only counts today: INVENTORY.md.

CI snippet for the owner (each frontend's workflow, after `npm ci`; not
added to `.github` by the builder):

```yaml
      - name: Brand lint (blocking for new feature code)
        run: >
          npx --no-install brand-lint src
          --block 'src/features/<feature>/**'
```

In customer-front-end use `node packages/brand/scripts/brand-lint.mjs src packages/site-kit/src --block ...`
(`npm run brand-lint` runs the report).

## 8. Pilots (Run 0)

| App | Pilot | Proves |
|---|---|---|
| admin | `src/shared/motion/BusyBar.tsx` renders `Bar variant="busy"`; old busy CSS removed from `shared/brand.css` | vendored package, Booqy theme, sticky busy strip |
| console | `src/components/BusyBar.tsx` renders `Bar variant="busy" position="fixed"`; old CSS removed from `styles.css` | React 18 consumer, English labels |
| guest | `src/features/kontakt/KontaktPage.tsx` "Skicka" is `Button` inside `data-bq-theme="restaurant"` | workspace link, restaurant colour via `--tenant-*` |
| booqy.se | the tour's step progress (`assets/booqy.js`, `.show-prog`) is a hairline progress Bar from `assets/brand/brand-static-0.1.0.{css,js}` | static copied assets, light-only tokens |
