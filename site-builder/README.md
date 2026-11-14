# site-builder

Site builder (feature B, `siteBuilder`): restaurant owners edit their site as
blocks, preview privately and publish; B1 in Run 1, AI edits and the
custom-code tier (B2) in Run 2.

- Decision record: `docs/adr/ADR-B-site-builder.md`; contract: `docs/build/CONTRACTS.md`
  (feature B, sections 0, 4, 5, 6.B, 7, 8.4 and 12).
- Resources: table `<prefix>site-builder`, Lambdas `site-builder` (Python:
  API, Validate/Promote/MarkFailed, purge) and `site-builder-render` (Node 22
  image from customer-front-end `render-lambda/`), Standard state machine
  `<prefix>site-builder-publish` (`definitions/publish.asl.json`, JSONata:
  Validate -> Render, skipped for rollback -> Promote; Catch -> MarkFailed),
  Errors and failed-execution alarms. `site-builder-render` gets
  `MENU_IMAGE_BASE_URL` (the public CloudFront distribution that serves
  `/menu-images/*`, same value as `sites/`); without it rendered pages have
  no images.
- Routes: `network/api-gateway/site-builder-routes.tf`; B8 is public with
  the public throttle.
- IAM (new roles only; **call out**): `site-builder` gets s3 Get/Put/Delete
  on `sites/*` and ListBucket with prefix `sites/*` on the sites bucket, and
  UpdateItem on the tenant table limited to the attributes `PK`, `SK`,
  `site` (`dynamodb:Attributes`); `site-builder-render` gets s3 PutObject on
  `sites/*/v/*`. Tenant scoping of keys is in code. The sites deploy roles,
  `deploy_boundary` and the OIDC roles are NOT changed.
- Owner action: the render image is built in the customer-front-end
  pipeline (ADR-B open question 1); until that workflow pushes it, the
  function runs the placeholder image and every publish fails at Render
  (feature is off for every tenant).
- **Do not switch a tenant to builder mode while its site repo workflow
  still deploys to the root.** The tenant's own site repo (`sites/`,
  template workflow) syncs its build to `sites/<t>/` and Promote copies the
  builder pages to the same root and deletes root pages it does not own, so
  the two overwrite each other on every deploy or publish. First disable (or
  repoint) the repo's deploy workflow, then turn on `siteBuilder` and publish.
