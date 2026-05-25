variable "bootstrap_password" {
  description = "Initial Rancher admin password set by Helm in 01-bootstrap. Re-used here to authenticate the first-time bootstrap call; can be empty on re-applies."
  type        = string
  sensitive   = true
}

variable "rancher_admin_password" {
  description = "Permanent admin password Rancher should use after bootstrap."
  type        = string
  sensitive   = true
}
