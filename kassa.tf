# Kassa, the till, was removed on 2026-11-14 (Booqy is online only). Only its
# two tables are left, at their old addresses (module.kassa), because
# kassaregister data is bookkeeping material kept at least 7 years
# (BFL 7 kap. 2 §). Nothing reads or writes them any more. In dev they are
# empty (the test data was deleted); in prod they were empty when Kassa was
# removed and keep deletion protection. No moved or removed blocks: CI's
# targeted ECR apply refuses pending moves.

module "kassa" {
  source      = "./kassa"
  environment = var.env
}
