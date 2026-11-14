# Kassa, the till, was removed on 2026-11-14 (Booqy is online only). Its two
# tables are kept in prod only, as bookkeeping material for 7 years
# (./kassa-records). The moved blocks take the tables from the old module
# address:
#   prod: module.kassa_records[0] is declared, the tables only change address
#         (no destroy, no create).
#   dev:  module.kassa_records[0] is not declared (count = 0), so the moved
#         objects are planned for destroy ("not in configuration"); dev has
#         no deletion protection on them.

module "kassa_records" {
  source      = "./kassa-records"
  count       = var.env == "prod" ? 1 : 0
  environment = var.env
}

moved {
  from = module.kassa.aws_dynamodb_table.kassa
  to   = module.kassa_records[0].aws_dynamodb_table.kassa
}

moved {
  from = module.kassa.aws_dynamodb_table.journal
  to   = module.kassa_records[0].aws_dynamodb_table.journal
}

moved {
  from = module.kassa.aws_dynamodb_resource_policy.journal_append_only
  to   = module.kassa_records[0].aws_dynamodb_resource_policy.journal_append_only
}
