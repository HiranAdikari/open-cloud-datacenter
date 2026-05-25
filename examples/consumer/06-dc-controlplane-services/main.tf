# Layer 06: DC-Controlplane Services
#
# Deploys dc-api + cloud-ui onto the dcapi-controlplane cluster created by
# layer 05. Calls modules/management/dc-controlplane-services.

terraform {
  required_providers {
    kubernetes = { source = "hashicorp/kubernetes", version = "~> 2.30" }
    helm       = { source = "hashicorp/helm", version = "~> 2.15" }
    rancher2   = { source = "rancher/rancher2", version = "~> 6.0" }
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

data "terraform_remote_state" "identity" {
  backend = "local"
  config  = { path = "../04-identity/terraform.tfstate" }
}

data "terraform_remote_state" "dc_controlplane" {
  backend = "local"
  config  = { path = "../05-dc-controlplane/terraform.tfstate" }
}

locals {
  ocd_ref = "v0.8.2"

  # Kubeconfig pointing at the dcapi-controlplane cluster's Kubernetes
  # apiserver via Rancher's proxy. Used by the kubernetes / helm providers
  # AND passed into the module for its internal helm-CLI bypass calls.
  dcapi_apiserver = "${data.terraform_remote_state.bootstrap.outputs.rancher_url}/k8s/clusters/${data.terraform_remote_state.dc_controlplane.outputs.dcapi_cluster_v3_id}"

  helm_kubeconfig = yamlencode({
    apiVersion        = "v1"
    kind              = "Config"
    "current-context" = "dcapi"
    clusters = [{
      name = "dcapi"
      cluster = {
        server                     = local.dcapi_apiserver
        "insecure-skip-tls-verify" = true
      }
    }]
    contexts = [{
      name    = "dcapi"
      context = { cluster = "dcapi", user = "dcapi" }
    }]
    users = [{
      name = "dcapi"
      user = { token = data.terraform_remote_state.rancher_auth.outputs.admin_token }
    }]
  })
}

provider "kubernetes" {
  host                   = local.dcapi_apiserver
  token                  = data.terraform_remote_state.rancher_auth.outputs.admin_token
  insecure               = true
}

provider "helm" {
  kubernetes {
    host                   = local.dcapi_apiserver
    token                  = data.terraform_remote_state.rancher_auth.outputs.admin_token
    insecure               = true
  }
}

module "dc_controlplane_services" {
  source = "github.com/wso2/open-cloud-datacenter//modules/management/dc-controlplane-services?ref=${local.ocd_ref}"

  oidc_issuer   = data.terraform_remote_state.identity.outputs.oidc_issuer_url
  oidc_audience = compact([
    data.terraform_remote_state.identity.outputs.rancher_oidc_client_id,
    var.bff_client_id,
    var.dcctl_client_id,
  ])

  rancher_url   = data.terraform_remote_state.bootstrap.outputs.rancher_url
  rancher_token = data.terraform_remote_state.rancher_auth.outputs.admin_token

  harvester_cloud_credential_id = data.terraform_remote_state.management.outputs.cloud_credential_id
  harvester_kubeconfig          = file(var.harvester_kubeconfig_path)
  helm_kubeconfig               = local.helm_kubeconfig

  dc_api_image     = var.dc_api_image
  dcapi_hostname   = var.dcapi_hostname
  cloudui_image    = var.cloud_ui_image
  cloudui_hostname = var.cloud_ui_hostname

  tenant_group_prefix = var.tenant_group_prefix
  admin_group         = var.admin_group
  log_level           = var.log_level

  operator_ssh_key  = var.operator_ssh_key
  operator_password = var.operator_password

  ghcr_username = var.ghcr_username
  ghcr_pat      = var.ghcr_pat

  # ARC (Actions Runner Controller) — optional CI surface. Leave blank to
  # skip; set if you want self-hosted runners for image rebuilds.
  github_repo_url   = var.github_repo_url
  github_runner_pat = var.github_runner_pat
  arc_chart_version = var.arc_chart_version

  # F7 BFF — confidential client cloud-ui uses to talk to dc-api.
  bff_client_id            = var.bff_client_id
  bff_client_secret        = var.bff_client_secret
  bff_session_secret       = var.bff_session_secret
  bff_redirect_url         = "https://${var.cloud_ui_hostname}/v1/auth/callback"
  bff_post_login_redirect  = "https://${var.cloud_ui_hostname}/"
  bff_post_logout_redirect = "https://${var.cloud_ui_hostname}/login"
  bff_cookie_domain        = var.cloud_ui_hostname
  bff_cookie_secure        = true

  vpc_external_reserved_ips = var.vpc_external_reserved_ips
  vpc_external_vlan_id      = var.vpc_external_vlan_id
}

# AES-256 session secret used by dc-api's BFF for cookie signing. Stable
# across applies; rotate manually if you need to invalidate every session.
resource "random_bytes" "bff_session_secret" {
  length = 32
  lifecycle {
    prevent_destroy = true
    ignore_changes  = all
  }
}
