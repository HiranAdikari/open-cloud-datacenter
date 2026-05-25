variable "harvester_kubeconfig_path" {
  description = "Path to the Harvester kubeconfig — passed into the module so dc-api can manage Harvester resources."
  type        = string
}

variable "dc_api_image" {
  description = "Container image for dc-api."
  type        = string
  default     = "ghcr.io/wso2/dc-api:v0.9.0"
}

variable "cloud_ui_image" {
  description = "Container image for cloud-ui."
  type        = string
  default     = "ghcr.io/wso2/cloud-ui:v0.9.0"
}

variable "dcapi_hostname" {
  description = "Public hostname dc-api serves at."
  type        = string
}

variable "cloud_ui_hostname" {
  description = "Public hostname cloud-ui serves at."
  type        = string
}

variable "tenant_group_prefix" {
  description = "Legacy IdP-group prefix dc-api uses for autoprovision (default dc-tenant-). To be removed in a future dc-api release — see FOLLOWUPS in the source repo."
  type        = string
  default     = "dc-tenant-"
}

variable "admin_group" {
  description = "Single IdP group whose members are platform admins."
  type        = string
  default     = "dc-admin"
}

variable "log_level" {
  description = "dc-api log level — debug | info | warn | error."
  type        = string
  default     = "info"
}

variable "operator_ssh_key" {
  description = "SSH public key the platform may inject into operator-owned VMs (e.g. bastions). Trim whitespace before passing."
  type        = string
  default     = ""
}

variable "operator_password" {
  description = "Console password the platform may set on operator-owned VMs."
  type        = string
  sensitive   = true
  default     = ""
}

variable "ghcr_username" {
  description = "GHCR username for pulling private images. Leave blank for canonical public ghcr.io/wso2/* images."
  type        = string
  default     = ""
}

variable "ghcr_pat" {
  description = "GHCR personal-access token with read:packages."
  type        = string
  sensitive   = true
  default     = ""
}

# OIDC clients — created manually on your IdP (see docs/prerequisites.md)
# and supplied via terraform.tfvars.

variable "bff_client_id" {
  description = "Confidential OIDC client ID for cloud-ui's BFF."
  type        = string
}

variable "bff_client_secret" {
  description = "Confidential OIDC client secret for cloud-ui's BFF."
  type        = string
  sensitive   = true
}

variable "bff_session_secret" {
  description = "Override the auto-generated AES-256 session secret. Leave blank to use the generated one."
  type        = string
  sensitive   = true
  default     = ""
}

variable "dcctl_client_id" {
  description = "Public PKCE OIDC client ID for dcctl."
  type        = string
}

# ARC (Actions Runner Controller) — leave blank to skip.

variable "github_repo_url" {
  description = "GitHub repo URL ARC runners listen against. Empty disables ARC."
  type        = string
  default     = ""
}

variable "github_runner_pat" {
  description = "GitHub PAT for ARC runner registration."
  type        = string
  sensitive   = true
  default     = ""
}

variable "arc_chart_version" {
  description = "Helm chart version for actions-runner-controller."
  type        = string
  default     = "0.27.0"
}

# KubeOVN VPC settings (used by dc-api for tenant VPC external IPAM).

variable "vpc_external_reserved_ips" {
  description = "Comma-separated IPs the platform must NOT allocate from KubeOVN's VPC external pool."
  type        = string
  default     = ""
}

variable "vpc_external_vlan_id" {
  description = "VLAN ID for the external VPC network. 0 = untagged."
  type        = number
  default     = 0
}
