# Example: Provision a tenant RKE2 Kubernetes cluster on Harvester
#
# This example provisions a 3-node RKE2 cluster for a tenant team using
# Rancher's machine provisioning API. Harvester acts as the infrastructure
# provider via a cloud credential created by the harvester-integration module.
#
# Prerequisites:
#   - Rancher deployed and Harvester integrated (harvester-integration module)
#   - A Harvester cloud credential named "harvester-local-creds" present in
#     Rancher (created automatically by the harvester-integration module)
#   - OS images and VLAN networks provisioned in Harvester (storage and
#     networking modules)
#   - The rancher2 provider configured with your Rancher URL and access key

terraform {
  required_version = ">= 1.7"

  required_providers {
    rancher2 = {
      source  = "rancher/rancher2"
      version = "~> 13.1"
    }
  }
}

provider "rancher2" {
  api_url = "https://rancher.example.internal"
  # Provide credentials via CATTLE_ACCESS_KEY / CATTLE_SECRET_KEY env vars
  # insecure = true # Only enable if using self-signed certs without pinning CA certs (Bootstrap only)
}

module "tenant_cluster" {
  source = "github.com/wso2-enterprise/open-cloud-datacenter//modules/workloads/k8s-cluster?ref=v0.2.0"

  cluster_name        = "tenant-alpha"
  kubernetes_version  = "v1.32.13+rke2r1"
  cloud_credential_id = "cattle-global-data:cc-xxxx"

  # Reference the image and network created by the storage and networking modules
  machine_pools = [
    {
      name          = "pool1"
      vm_namespace  = "default"
      quantity      = 3
      cpu_count     = "4"
      memory_size   = "16"
      disk_size     = 100
      image_name    = "default/ubuntu-22-04"
      networks      = ["default/vlan-tenants", "iaas/storage-network"]
      control_plane = true
      etcd          = true
      worker        = true
    }
  ]

  ssh_user = "ubuntu"
}
