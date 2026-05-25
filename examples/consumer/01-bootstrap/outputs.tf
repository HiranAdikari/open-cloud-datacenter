output "rancher_hostname" {
  description = "FQDN of the bootstrapped Rancher server."
  value       = module.rancher_bootstrap.rancher_hostname
}

output "rancher_url" {
  description = "Base URL for Rancher, derived from rancher_hostname."
  value       = "https://${module.rancher_bootstrap.rancher_hostname}"
}

output "rancher_lb_ip" {
  description = "IP the Rancher LB is reachable at."
  value       = module.rancher_bootstrap.rancher_lb_ip
}

output "vm_image_id" {
  description = "Harvester image reference (namespace/name) for the OS image. Re-use in 05-dc-controlplane."
  value       = module.rancher_bootstrap.vm_image_id
}
