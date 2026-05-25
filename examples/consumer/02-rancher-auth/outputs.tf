output "admin_token" {
  description = "Rancher admin API token. Consumed by every downstream layer via terraform_remote_state."
  value       = rancher2_bootstrap.admin.token
  sensitive   = true
}
