output "harvester_cluster_id" {
  description = "Rancher's cluster ID for the registered Harvester cluster."
  value       = module.harvester_integration.harvester_cluster_id
}

output "harvester_cluster_name" {
  description = "Name Harvester is registered under in Rancher."
  value       = module.harvester_integration.harvester_cluster_name
}

output "cloud_credential_id" {
  description = "Rancher Harvester cloud credential ID. Consumed by 05-dc-controlplane to provision RKE2 VMs on Harvester."
  value       = module.harvester_integration.cloud_credential_id
}

output "harvester_api_server" {
  description = "Direct Harvester kube-apiserver URL. Used by per-tenant credential / VM-access modules."
  value       = module.harvester_integration.harvester_api_server
  sensitive   = true
}
