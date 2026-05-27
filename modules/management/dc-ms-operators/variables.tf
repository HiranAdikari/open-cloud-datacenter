# dc-ms-operators umbrella — inputs
#
# Per-operator toggles let consumers pick à-la-carte:
#   - Consumers that run dc-api + cloudui MUST enable every operator
#     dc-api expects to dispatch CRs to (today: keyvault).
#   - Consumers that just want a single operator on their harvester
#     (no dc-api) set enable_<other> = false.
#
# Per-operator config is flat (prefixed). Adding a new operator =
# new `enable_<name>` + `<name>_*` vars here + a new sub-module
# directory + a new `module "<name>"` block in main.tf.

# ── keyvault ─────────────────────────────────────────────────────────────────
variable "enable_keyvault" {
  type        = bool
  description = "Deploy the keyvault operator. Required when consumer also runs dc-api+cloudui (dc-api dispatches KeyVaultBackend/KeyVaultInstance CRs to it)."
  default     = true
}

variable "keyvault_image" {
  type        = string
  description = "Image (no tag) for the keyvault operator. e.g. ghcr.io/<org>/keyvault-operator."
  default     = "ghcr.io/hiranadikari/keyvault-operator"
}

variable "keyvault_image_tag" {
  type        = string
  description = "Pinned tag for the keyvault operator image. Bump deliberately on operator releases."
  default     = "v0.0.1"
}

variable "keyvault_namespace" {
  type        = string
  description = "Namespace to deploy the keyvault operator into."
  default     = "keyvault-system"
}

variable "keyvault_enable_metrics_network_policy" {
  type        = bool
  description = "Apply NetworkPolicy gating metrics traffic to Prometheus pods only."
  default     = false
}

variable "keyvault_enable_prometheus_servicemonitor" {
  type        = bool
  description = "Apply the ServiceMonitor CR for Prometheus scraping. Requires Prometheus Operator CRDs on the target cluster."
  default     = false
}

variable "keyvault_enable_cert_manager_metrics" {
  type        = bool
  description = "Wire cert-manager to issue a TLS cert for the operator's metrics endpoint. Requires cert-manager on the target cluster."
  default     = false
}

# ── shared image-pull cred ───────────────────────────────────────────────────
# All current sub-modules pull from the same ghcr.io org. If a future
# operator pulls from elsewhere, split these into per-operator vars.

variable "ghcr_username" {
  type        = string
  description = "GitHub username for ghcr.io image pulls. Leave null if operator images are public."
  default     = null
}

variable "ghcr_pat" {
  type        = string
  description = "GitHub PAT with read:packages scope. Leave null if operator images are public."
  sensitive   = true
  default     = null
}
