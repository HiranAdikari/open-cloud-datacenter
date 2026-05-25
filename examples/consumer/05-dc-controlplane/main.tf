# Layer 05: DC-Controlplane
#
# Provisions the dcapi-controlplane RKE2 cluster on Harvester via Rancher.
# This is the cluster that will host dc-api / cloud-ui / managed-service
# operators (layers 06 + 07). Calls modules/management/dc-controlplane.

terraform {
  required_providers {
    rancher2   = { source = "rancher/rancher2", version = "~> 6.0" }
    harvester  = { source = "harvester/harvester", version = "~> 0.6" }
    kubernetes = { source = "hashicorp/kubernetes", version = "~> 2.30" }
  }
}

data "terraform_remote_state" "bootstrap" {
  backend = "local"
  config  = { path = "../01-bootstrap/terraform.tfstate" }
}

data "terraform_remote_state" "rancher_auth" {
  backend = "local"
  config  = { path = "../02-rancher-auth/terraform.tfstate" }
}

data "terraform_remote_state" "management" {
  backend = "local"
  config  = { path = "../03-management/terraform.tfstate" }
}

provider "rancher2" {
  api_url   = data.terraform_remote_state.bootstrap.outputs.rancher_url
  token_key = data.terraform_remote_state.rancher_auth.outputs.admin_token
  insecure  = true
}

provider "harvester" {
  kubeconfig = var.harvester_kubeconfig_path
}

provider "kubernetes" {
  alias       = "harvester"
  config_path = var.harvester_kubeconfig_path
}

locals {
  ocd_ref = "v0.8.2"
}

module "dc_controlplane" {
  source = "github.com/wso2/open-cloud-datacenter//modules/management/dc-controlplane?ref=${local.ocd_ref}"

  providers = {
    rancher2             = rancher2
    harvester            = harvester
    kubernetes.harvester = kubernetes.harvester
  }

  cluster_name              = var.dcapi_cluster_name
  project_name              = var.dcapi_project_name
  kubernetes_version        = var.dcapi_kubernetes_version
  harvester_cluster_id      = data.terraform_remote_state.management.outputs.harvester_cluster_id
  cloud_credential_id       = data.terraform_remote_state.management.outputs.cloud_credential_id
  harvester_kubeconfig_path = var.harvester_kubeconfig_path

  # LoadBalancer VIPs for the dcapi cluster (apiserver, ingress)
  lb_range_start = var.dcapi_lb_range_start
  lb_range_end   = var.dcapi_lb_range_end
  lb_subnet      = var.lb_subnet
  lb_gateway     = var.lb_gateway

  # 1-node dev / 3-node HA. For a real production deployment use 3 nodes
  # so etcd has quorum and kube-vip leader election is meaningful.
  machine_pools = [
    {
      name          = "controlplane"
      quantity      = var.dcapi_node_count
      cpu_count     = "8"
      memory_size   = "16Gi"
      disk_size     = 80
      image_name    = data.terraform_remote_state.bootstrap.outputs.vm_image_id
      networks      = []  # populated by the module from mgmt_cluster_network + project NAD
      control_plane = true
      etcd          = true
      worker        = true
    }
  ]

  # Defaults inside the module set sensible Kubernetes-args (etcd healthcheck
  # timeout, leader-elect tuning). Override only if you have specific needs.
  manage_rke_config     = true
  machine_global_config = null  # use module default

  # Cloud-init user_data for each node. The module bakes basic packages +
  # qemu-guest-agent. Customise via your own template if needed.
  user_data = file("${path.module}/user-data.yaml")
}
