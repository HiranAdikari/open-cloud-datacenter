# dc-ms-operators umbrella — composes per-operator sub-modules.
#
# Consumers either:
#   1. Call THIS module and toggle individual operators on/off
#      (recommended when running dc-api+cloudui — wire all operators
#      that dc-api dispatches to).
#   2. Call a sub-module directly, e.g.
#      `source = ".../dc-ms-operators/keyvault"`, for à-la-carte
#      consumers who don't want the umbrella's input surface.
#
# Provider passthrough: caller supplies a `kubernetes` provider
# configured for the target cluster (typically harvester-dev). All
# sub-modules inherit it via the `providers` block.

module "keyvault" {
  count  = var.enable_keyvault ? 1 : 0
  source = "./keyvault"

  providers = {
    kubernetes = kubernetes
  }

  kv_image     = var.keyvault_image
  kv_image_tag = var.keyvault_image_tag
  kv_namespace = var.keyvault_namespace

  enable_metrics_network_policy    = var.keyvault_enable_metrics_network_policy
  enable_prometheus_servicemonitor = var.keyvault_enable_prometheus_servicemonitor
  enable_cert_manager_metrics      = var.keyvault_enable_cert_manager_metrics

  ghcr_username = var.ghcr_username
  ghcr_pat      = var.ghcr_pat
}

# Future operators slot in here:
#
# module "postgres" {
#   count  = var.enable_postgres ? 1 : 0
#   source = "./postgres"
#   ...
# }
#
# module "redis" {
#   count  = var.enable_redis ? 1 : 0
#   source = "./redis"
#   ...
# }
