# ─────────────────────────────────────────────────────────────────────────────
# dc-ms-operators module — inputs
#
# Variables shared across all managed-service operator controllers deployed
# by this module. Per-operator variables are prefixed (e.g. kv_*) so the
# namespace stays clean when DB, cache, and registry operators are added.
# ─────────────────────────────────────────────────────────────────────────────

# ── Keyvault operator ─────────────────────────────────────────────────────────

variable "kv_namespace" {
  type        = string
  description = "Namespace the keyvault-operator controller runs in. Must exist or be created by this module (default: 'keyvault-system')."
  default     = "keyvault-system"
}

variable "kv_image" {
  type        = string
  description = "Container image registry path for the keyvault-operator, without a tag (e.g. 'ghcr.io/hiranadikari/keyvault-operator')."
  default     = "ghcr.io/hiranadikari/keyvault-operator"
}

variable "kv_image_tag" {
  type        = string
  description = "Pinned image tag for the keyvault-operator. Never 'latest' — a fixed tag ensures plan output is deterministic and rollback is possible."
  default     = "v0.0.1"
}

# ── GHCR image pull credentials (optional) ────────────────────────────────────
# Both must be set together. If either is empty the pull secret is skipped and
# the Deployment has no imagePullSecrets — suitable for clusters that already
# have cluster-level registry credentials or when the image is public.

variable "ghcr_username" {
  type        = string
  description = "GitHub username for pulling images from ghcr.io. Set together with ghcr_pat to create a 'ghcr-pull-secret' in each operator namespace. Leave empty for public images or clusters with pre-existing registry credentials."
  default     = ""
}

variable "ghcr_pat" {
  type        = string
  sensitive   = true
  description = "GitHub Personal Access Token with read:packages scope. Required when ghcr_username is set. Stored as a kubernetes.io/dockerconfigjson Secret in the operator namespace."
  default     = ""
}
