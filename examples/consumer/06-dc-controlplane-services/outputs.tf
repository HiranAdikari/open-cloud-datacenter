output "dc_api_url" {
  description = "Public URL of the dc-api ingress. The wrapper polls /healthz here for the readiness gate."
  value       = "https://${var.dcapi_hostname}"
}

output "cloud_ui_url" {
  description = "Public URL of the cloud-ui ingress."
  value       = "https://${var.cloud_ui_hostname}"
}

output "postgres_password" {
  description = "Auto-generated Postgres password for dc-api's database. Used internally by dc-api."
  value       = module.dc_controlplane_services.postgres_password
  sensitive   = true
}
