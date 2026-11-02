# ADR-BRAND: How the repos share the brand system

**Status:** Proposed (package home decided by the owner)
**Date:** 2026-11-01
**Deciders:** Owner (package home), brand guardian (consumption per repo)
**Run:** Run 0 step 8b builds it; Runs 1-2 consume it; Run 3 migrates all UI

## Context

The look is copied, not shared (INVENTORY.md): admin, the console, the guest
site and booqy.se each carry their own tokens, press/sound engine, glide,
glass filter, theme switch, skeletons and loaders, and eight emails carry
their own palettes. The repos are separate (`admin-front-end`,
`booqy-console`, `customer-front-end`, `booqy-website`, `application`,
`infrastructure`), each with its own CI that checks out only itself.
booqy.se is plain HTML with no build step. Emails are inline-styled Python.
The console runs React 18, admin and the guest site React 19.

The owner decided the package's home: `customer-front-end/packages/brand`,
named `@booqy/brand`, structured and published to GitHub Packages exactly
like `packages/site-kit` (three-condition exports with `"@booqy/source"`, a
lib build, `files`, `publishConfig`).

## Decision

1. **Package.** `customer-front-end/packages/brand` (`@booqy/brand` 0.1.0):
   exports `.` (`@booqy/source` -> `src/index.ts`, `types`, `default` ->
   `dist`), `./styles.css`, `./tokens.json`, `./email-tokens.json`; lib build
   with React external; `files: dist, tokens.json, scripts/brand-lint.mjs,
   README, CHANGELOG`; `publishConfig.registry: https://npm.pkg.github.com`;
   bin `brand-lint`. Peers `react`/`react-dom` `^18.3.0 || ^19.0.0` (the
   console is on 18; a 19-only peer would make its `npm ci` fail). Tokens
   come from one `tokens.json`; everything else is generated.
2. **customer-front-end (guest site, site-kit): workspace link.** The root
   `package.json` depends on `"@booqy/brand": "0.1.0"`; npm workspaces link
   `node_modules/@booqy/brand` to `packages/brand`; the app resolves the
   `@booqy/source` condition (already configured for site-kit), so dev, tests
   and build read the source with no prebuild. Root `build` and `test` run the
   package first.
3. **admin-front-end and booqy-console/web: npm dependency from GitHub
   Packages, vendored tarball until the first publish.** Until the package is
   published, each repo commits the packed build `vendor/booqy-brand-0.1.0.tgz`
   (`npm pack` of the package, 74 kB) and depends on
   `"@booqy/brand": "file:vendor/booqy-brand-0.1.0.tgz"`; the lockfile pins
   its sha512. Chosen over a `file:../customer-front-end/packages/brand` path
   because each repo's CI checks out only itself (a sibling path does not
   exist there and would differ per laptop), and over a git dependency
   because that needs cross-repo credentials and a build on install. The
   tarball is exactly what will be published, so switching is one line.
   Run 1 builders that need a newer brand ask the single brand guardian
   builder (`build/brand-additions`), who bumps the version, re-packs and
   updates the tarball and lockfile in the consuming repos.
   After the first publish: `"@booqy/brand": "npm:@bookingsystemadvancedorg/brand@^0.1.0"`,
   an `.npmrc` line `@bookingsystemadvancedorg:registry=https://npm.pkg.github.com`,
   `NODE_AUTH_TOKEN` in CI, and delete `vendor/`.
4. **booqy.se: copied built assets with a version stamp.** The package
   builds a no-React IIFE (`window.BooqyBrand`) and a light-only stylesheet:
   `dist/static/brand-static-<version>.{js,css}`. They are copied into
   `booqy-website/site/assets/brand/` with the version in the file name (so
   CloudFront can cache them for a year and an update is a new name), linked
   before `booqy.css` / `booqy.js` on the pages that use them. Updating =
   copy the new pair, change the two names in the pages, delete the old pair.
5. **Emails: token values as JSON and Python constants.** The build writes
   `email-tokens.json` and `booqy_brand_tokens.py` (flat light values: palette,
   semantic colours, font stacks, radii). Run 3 copies the Python file into
   `application/shared/` (and the console API) and the templates read the
   constants instead of hex literals. A test in each Python repo can compare
   the copy to the published JSON. The restaurant colour in guest emails stays
   the tenant's (`_brand_color`), the restaurant theme rule.
6. **Versioning.** Semver per CHANGELOG.md: removing or renaming an export, a
   Bar variant, a `--bq-*` variable or a `bq-` class is major.

## Publishing (snippet for the owner; `.github` is the owner's)

GitHub Packages only accepts npm packages scoped to the owner, so the
package is published as `@bookingsystemadvancedorg/brand` (as the standalone
site-kit is) while the workspace and every import keep `@booqy/brand`;
consumers use the npm alias in point 3. Tag `brand-v<version>` on `main`.
`customer-front-end/.github/workflows/publish-brand.yml`:

```yaml
# Publishes packages/brand to GitHub Packages as @bookingsystemadvancedorg/brand
# when a tag brand-v1.2.3 is pushed. The tag must match the package version and be on main.
name: Publish brand

on:
  push:
    tags: ["brand-v*"]

permissions:
  contents: read
  packages: write

jobs:
  publish:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0
      - name: The tag is the package version, on main
        run: |
          set -euo pipefail
          version=$(node -p "require('./packages/brand/package.json').version")
          [ "$GITHUB_REF_NAME" = "brand-v$version" ] || { echo "::error::tag $GITHUB_REF_NAME but packages/brand says $version"; exit 1; }
          git merge-base --is-ancestor "$GITHUB_SHA" origin/main || { echo "::error::$GITHUB_REF_NAME is not on main"; exit 1; }
      - uses: actions/setup-node@v4
        with:
          node-version: "24"
          cache: npm
          registry-url: https://npm.pkg.github.com
          scope: "@bookingsystemadvancedorg"
      - run: npm ci
      - run: npm run lint
      - run: npm test -w @booqy/brand
      - run: npm run build -w @booqy/brand
      - name: Publish under the org scope
        working-directory: packages/brand
        run: |
          npm pkg set name=@bookingsystemadvancedorg/brand
          npm publish
        env:
          NODE_AUTH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
```

Consumers' CI (`npm ci` step) then needs, once the vendored tarball is gone:

```yaml
      - uses: actions/setup-node@v4
        with:
          node-version: "24"
          registry-url: https://npm.pkg.github.com
          scope: "@bookingsystemadvancedorg"
      - run: npm ci
        env:
          NODE_AUTH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
```

and the package's settings on GitHub must grant read access to the
`admin-front-end` and `booqy-console` repositories (Package settings, Manage
Actions access). Human action, not code.

## Consequences

- One source for tokens, effects, the Bar family and components; Runs 1-2
  build new UI only from it, gated by `brand-lint` and the brand reviewer.
- Until the first publish, a brand change touches up to three repos (the
  package, plus the tarball and lockfile line in admin and the console).
  Acceptable for Run 1; publishing removes it.
- The vendored tarball is a 74 kB binary in two repos' history per version;
  delete `vendor/` after the switch.
- booqy.se carries a copy that can lag; its version is visible in the file
  name, and Run 3's consolidation updates it with the rest.
- Python templates hold a copy of the values; a drift test catches lag.

## Alternatives considered

- **git submodule** of the package into each repo: every repo then builds the
  package itself, submodule pointers drift silently, and CI needs recursive
  checkout with credentials. Rejected.
- **`file:` path to the sibling checkout:** works on a laptop only. Rejected.
- **A separate `brand` repo:** cleaner ownership but overruled by the owner's
  decision to keep it next to site-kit (the guest site is its first consumer).
- **CDN-hosted CSS/JS for every app:** a runtime dependency and a CSP change
  for admin and the console. Rejected; only booqy.se, which has no build,
  takes static files, and from its own origin.
