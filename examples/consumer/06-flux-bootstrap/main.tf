# Layer 06: Flux Bootstrap
#
# Installs Flux into the dcapi-controlplane cluster created by layer 05
# and points it at the operator's fork of this repo. From this point on,
# every in-cluster change is a commit to that fork — no more terraform
# applies for in-cluster workloads.
#
# Flow:
#   1. This layer applies Flux's "GitOps Toolkit" components to the cluster
#      (source-controller, kustomize-controller, helm-controller,
#       notification-controller, image-reflector-controller,
#       image-automation-controller).
#   2. It commits gotk-components.yaml + gotk-sync.yaml into the operator's
#      fork at flux/clusters/<env>/flux-system/.
#   3. Flux's root Kustomization then pulls flux/clusters/<env>/, which
#      brings in infrastructure (sealed-secrets, cert-manager, ingress-nginx)
#      and platform (dc-api, …) per the env's overlay.
#
# Equivalent to running `flux bootstrap github` by hand, but driven by
# the wrapper script so the operator doesn't need the flux CLI installed.

terraform {
  required_version = ">= 1.7"
  required_providers {
    flux = {
      source  = "fluxcd/flux"
      version = "~> 1.4"
    }
    github = {
      source  = "integrations/github"
      version = "~> 6.3"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.30"
    }
  }
}

data "terraform_remote_state" "bootstrap" {
  backend = "s3"
  config  = var.state_backend_config_bootstrap
}

data "terraform_remote_state" "rancher_auth" {
  backend = "s3"
  config  = var.state_backend_config_rancher_auth
}

data "terraform_remote_state" "dc_controlplane" {
  backend = "s3"
  config  = var.state_backend_config_dc_controlplane
}

locals {
  dcapi_apiserver = "${data.terraform_remote_state.bootstrap.outputs.rancher_url}/k8s/clusters/${data.terraform_remote_state.dc_controlplane.outputs.dcapi_cluster_v3_id}"
}

# Provider configs for the dcapi-controlplane cluster (via Rancher proxy).
provider "kubernetes" {
  host                   = local.dcapi_apiserver
  token                  = data.terraform_remote_state.rancher_auth.outputs.admin_token
  insecure               = true
}

provider "github" {
  owner = var.github_owner
  token = var.github_token
}

provider "flux" {
  kubernetes = {
    host                   = local.dcapi_apiserver
    token                  = data.terraform_remote_state.rancher_auth.outputs.admin_token
    insecure               = true
  }
  git = {
    url = "ssh://git@github.com/${var.github_owner}/${var.github_repository}.git"
    ssh = {
      username    = "git"
      private_key = tls_private_key.flux.private_key_pem
    }
  }
}

# Deploy key Flux will use to push image-automation commits back to the fork.
resource "tls_private_key" "flux" {
  algorithm   = "ECDSA"
  ecdsa_curve = "P256"
}

resource "github_repository_deploy_key" "flux" {
  title      = "flux-${var.env_name}"
  repository = var.github_repository
  key        = tls_private_key.flux.public_key_openssh
  read_only  = false # Flux Image Automation Controller commits manifest bumps.
}

# Install Flux components + write gotk-sync.yaml committed to flux/clusters/<env>/flux-system/.
resource "flux_bootstrap_git" "this" {
  depends_on = [github_repository_deploy_key.flux]

  embedded_manifests = true
  path               = "flux/clusters/${var.env_name}"
  namespace          = "flux-system"
}
