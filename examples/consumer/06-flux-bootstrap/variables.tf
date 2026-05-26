variable "env_name" {
  description = "Environment slug used as the directory name under flux/clusters/. E.g. 'lk-dev', 'customer-prod-eu'."
  type        = string
}

variable "github_owner" {
  description = "GitHub user or org owning the fork Flux will read from (and push image-automation commits back to)."
  type        = string
}

variable "github_repository" {
  description = "Repository name within github_owner (e.g. 'open-cloud-datacenter' or a renamed fork)."
  type        = string
  default     = "open-cloud-datacenter"
}

variable "git_branch" {
  description = "Branch Flux watches + commits gotk-sync.yaml to. Defaults to main; override to a feature branch when testing a spike."
  type        = string
  default     = "main"
}

variable "github_token" {
  description = "GitHub PAT with repo scope. Used for HTTPS git auth — stored as a Secret in the flux-system namespace and re-used by Flux for every subsequent git operation (clone + push for image-automation). Rotate by re-applying this layer with a new token."
  type        = string
  sensitive   = true
}

# Inputs to look up earlier layers' state. Default backend keys mirror
# layers 01/02/05's versions.tf; override the bucket/region for your env.
variable "state_backend_config_bootstrap" {
  description = "Terraform S3 backend config used to read layer 01-bootstrap's outputs."
  type        = map(string)
}

variable "state_backend_config_rancher_auth" {
  description = "Terraform S3 backend config used to read layer 02-rancher-auth's outputs."
  type        = map(string)
}

variable "state_backend_config_dc_controlplane" {
  description = "Terraform S3 backend config used to read layer 05-dc-controlplane's outputs."
  type        = map(string)
}
