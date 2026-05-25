variable "asgardeo_org_name" {
  description = "Asgardeo organisation name (the path segment in https://api.asgardeo.io/t/<org>)."
  type        = string
}

variable "asgardeo_management_client_id" {
  description = "Client ID of an Asgardeo M2M application with permission to create + manage other applications. Used by the asgardeo provider."
  type        = string
  sensitive   = true
}

variable "asgardeo_management_client_secret" {
  description = "Client secret of the M2M application above."
  type        = string
  sensitive   = true
}

variable "asgardeo_app_name" {
  description = "Display name for the Rancher-SSO application registered on Asgardeo."
  type        = string
  default     = "rancher-sso"
}

variable "skip_consent" {
  description = "Whether Asgardeo should skip the per-user consent prompt during login."
  type        = bool
  default     = true
}
