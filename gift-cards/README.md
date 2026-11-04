# gift-cards

Gift cards (feature E, `giftCards`): presentkort sold on the restaurant site,
issued only from Stripe, redeemed partly online and in Kassa, booked in
Bokföring. **VAT treatment (multi-purpose voucher) needs accountant review.**

- Decision record: `docs/adr/ADR-E-gift-cards.md`; contract: `docs/build/CONTRACTS.md`
  (feature E, sections 0, 4, 5, 6.E, 9, 10, 11 and 12).
- Resources: table `<prefix>gift-cards` with GSIs `byLocationDay` (TX rows,
  Bokföring) and sparse `byExpiry` (expiry and 24-month contact clean-up
  days), PITR, TTL, deletion protection in prod; Lambda `gift-cards`;
  secret `${prefix}gift-cards/code-pepper` (`random_password`, Terraform
  sets the value; never output); nightly schedule 02:30 Europe/Stockholm
  and its invoke role; Errors alarm.
- IAM (new role only, **owner to approve**): own table + both GSIs;
  GetSecretValue on the pepper, the platform Stripe key and the Turnstile
  secret; UpdateItem on the request-guard table; `lambda:InvokeFunction` on
  `notification:live` (code email); `events:PutEvents` with
  `events:source = booqy.gift-cards`; the tenant-context and staff-check
  read policies (wiring). Scheduler role: invoke `gift-cards:live`.
- No existing role changes here: the eight callers' invoke grants on
  `gift-cards:live` exist since Run 0 (CONTRACTS.md 14 rows 1-7, 5b).
- New stateful resources: the table and the pepper secret (deleting the
  pepper makes every issued code unusable).
- Routes: `network/api-gateway/gift-cards-routes.tf` (3 public with the
  public throttle, 10 jwt).
- ECR repository already exists (`module "gift_cards_ecr"` in `config.tf`).
