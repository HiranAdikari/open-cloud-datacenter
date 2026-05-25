# Layer 01: Bootstrap
#
# Provisions an RKE2-based Rancher server on Harvester via cloud-init.
# This layer ONLY creates the VM + installs Rancher. The permanent admin
# password + API token are set by 02-rancher-auth (kept separate because
# rancher2_bootstrap can only run after Rancher is reachable, which
# requires a wait the wrapper handles between layers).

terraform {
  required_providers {
    harvester  = { source = "harvester/harvester", version = "~> 0.6" }
    kubernetes = { source = "hashicorp/kubernetes", version = "~> 2.30" }
    tls        = { source = "hashicorp/tls", version = "~> 4.0" }
    null       = { source = "hashicorp/null", version = "~> 3.0" }
  }
}

provider "harvester" {
  kubeconfig = var.harvester_kubeconfig_path
}

provider "kubernetes" {
  config_path = var.harvester_kubeconfig_path
}

locals {
  # OCD release pin. Bump per layer when upgrading.
  ocd_ref = "v0.8.2"
}

module "rancher_bootstrap" {
  source = "github.com/wso2/open-cloud-datacenter//modules/bootstrap?ref=${local.ocd_ref}"

  # VM
  vm_name             = "rancher"
  harvester_namespace = var.harvester_namespace
  node_count          = var.node_count
  vm_cpu              = 8
  vm_memory           = "32Gi"
  vm_disk_name        = "disk-0"
  vm_disk_size        = "60Gi"
  vm_disk_auto_delete = true
  enable_usb_tablet   = true

  # OS image — downloaded into Harvester if not already present
  image_url           = var.image_url
  image_display_name  = "ocd-ubuntu-rancher"

  # Network
  network_type           = var.network_type
  network_interface_name = "default"
  network_name           = var.network_name

  # SSH + cloud-init — let the module generate everything for a fresh install
  create_ssh_key            = true
  create_cloudinit_secret   = true
  vm_password               = var.vm_password
  harvester_kubeconfig_path = var.harvester_kubeconfig_path

  # Rancher install
  rancher_hostname   = var.rancher_hostname
  bootstrap_password = var.bootstrap_password
  rke2_version       = var.rke2_version
  rancher_version    = var.rancher_version
  tls_source         = var.tls_source

  # LoadBalancer + IP pool
  create_lb           = var.create_lb
  ippool_start        = var.ippool_start
  ippool_end          = var.ippool_end
  ippool_subnet       = var.ippool_subnet
  ippool_gateway      = var.ippool_gateway
  ippool_network_name = var.ippool_network_name
  static_rancher_ip   = var.static_rancher_ip

  # Storage class — set Longhorn 2-replica as the cluster default
  manage_storage_class = true
}
