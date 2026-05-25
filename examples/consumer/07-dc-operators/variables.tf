variable "harvester_kubeconfig_path" {
  description = "Path to the Harvester kubeconfig — needed by dc-webhook to talk to Harvester."
  type        = string
}

variable "dc_webhook_image" {
  description = "Container image for dc-webhook."
  type        = string
  default     = "ghcr.io/wso2/dc-webhook:v0.9.0"
}

variable "webhook_domain" {
  description = "DNS-safe domain stamp for the webhook's certificate SAN. Defaults to a value compatible with cluster-internal traffic."
  type        = string
  default     = "dc-webhook.svc"
}

variable "log_level" {
  description = "dc-webhook log level."
  type        = string
  default     = "info"
}

variable "ghcr_username" {
  description = "GHCR username for pulling private images."
  type        = string
  default     = ""
}

variable "ghcr_pat" {
  description = "GHCR PAT with read:packages."
  type        = string
  sensitive   = true
  default     = ""
}
