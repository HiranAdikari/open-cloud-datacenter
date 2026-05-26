output "external_provider_network_name" {
  description = "Name of the external ProviderNetwork. dc-api reads this from DCAPI_VPC_EXTERNAL_BRIDGE indirectly (via the bridge name)."
  value       = var.external_provider_network_name
}

output "external_subnet_name" {
  description = "Name of the ovn-vpc-external-network subnet. dc-api creates the NAD wrapping this subnet at startup."
  value       = "ovn-vpc-external-network"
}

output "external_bridge" {
  description = "Host bridge name. Passed to dc-api as DCAPI_VPC_EXTERNAL_BRIDGE."
  value       = var.external_bridge
}

output "external_cidr" {
  description = "External CIDR. Passed to dc-api as DCAPI_VPC_EXTERNAL_CIDR."
  value       = var.external_cidr
}

output "external_gateway" {
  description = "External gateway IP. Passed to dc-api as DCAPI_VPC_EXTERNAL_GATEWAY."
  value       = var.external_gateway
}

output "external_vlan_id" {
  description = "External VLAN ID. Passed to dc-api as DCAPI_VPC_EXTERNAL_VLAN_ID."
  value       = var.external_vlan_id
}
