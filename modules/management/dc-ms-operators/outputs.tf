# Per-sub-module pass-through outputs. Null when the operator is
# disabled — consumers can `try()` or `coalesce()` to detect.

output "keyvault_namespace" {
  description = "Namespace the keyvault operator was deployed into. Null when enable_keyvault = false."
  value       = var.enable_keyvault ? module.keyvault[0].kv_namespace : null
}

output "keyvault_deployment_name" {
  description = "Name of the keyvault operator Deployment. Null when enable_keyvault = false."
  value       = var.enable_keyvault ? module.keyvault[0].kv_deployment_name : null
}

output "keyvault_image" {
  description = "Fully-qualified image:tag actually applied for the keyvault operator. Null when enable_keyvault = false."
  value       = var.enable_keyvault ? module.keyvault[0].kv_image : null
}
