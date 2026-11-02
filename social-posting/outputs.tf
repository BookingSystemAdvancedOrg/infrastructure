# Merged by the root config.tf (local.feature_wiring) into lambda releases,
# the tenant-context policy and the API Gateway integrations. Fixed shape
# (CONTRACTS.md 12.2); empty until the feature's functions exist.
output "wiring" {
  value = {
    lambda_releases         = {} # "<fn name>" => { alias_name = "live" }
    tenant_aware_role_names = {} # "<fn_name_underscored>" => role name
    staff_check_role_names  = {} # same keys, functions where staff act
    api_integrations        = {} # "<feature-id>" => { function_name, invoke_arn }
  }
}
