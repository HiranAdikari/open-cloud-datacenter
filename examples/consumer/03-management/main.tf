# Layer 03: Management
#
# Registers Harvester into Rancher and stages the cloud credential downstream
# layers (workloads/k8s-cluster, dc-controlplane) need to provision RKE2
# clusters on top of Harvester. Calls modules/management/harvester-integration.
#
# Additional management modules — networking, storage, rbac, cluster-roles,
# tenant-space — are intentionally not called from this minimal template.
# Add them when you start onboarding tenants or curating image catalogues.

terraform {
  required_providers {
    rancher2   = { source = "rancher/rancher2", version = "~> 6.0" }
    kubernetes = { source = "hashicorp/kubernetes", version = "~> 2.30" }
  }
}

data "terraform_remote_state" "bootstrap" {
  backend = "local"
  config = {
    path = "../01-bootstrap/terraform.tfstate"
  }
}

data "terraform_remote_state" "rancher_auth" {
  backend = "local"
  config = {
    path = "../02-rancher-auth/terraform.tfstate"
  }
}

provider "rancher2" {
  api_url   = data.terraform_remote_state.bootstrap.outputs.rancher_url
  token_key = data.terraform_remote_state.rancher_auth.outputs.admin_token
  insecure  = true
}

provider "kubernetes" {
  config_path = var.harvester_kubeconfig_path
}

locals {
  ocd_ref = "v0.8.2"
}

module "harvester_integration" {
  source = "github.com/wso2/open-cloud-datacenter//modules/management/harvester-integration?ref=${local.ocd_ref}"

  harvester_kubeconfig   = file(var.harvester_kubeconfig_path)
  harvester_cluster_name = var.harvester_cluster_name
  rancher_hostname       = data.terraform_remote_state.bootstrap.outputs.rancher_hostname
  rancher_lb_ip          = data.terraform_remote_state.bootstrap.outputs.rancher_lb_ip
}
