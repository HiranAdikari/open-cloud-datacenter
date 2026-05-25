# Layer 07: DC-Operators
#
# Installs managed-service operators onto the dcapi-controlplane cluster:
#   - dc-webhook  (admission webhook supporting dc-api tenant-isolation)
#   - keyvault-operator (KVI — Key Vault Instance reconciler)
#
# The keyvault operator does not (yet) ship as an OCD TF module — the
# manifests live at crds/keyvault/config/* in this repo. For now this
# layer applies dc-webhook via the OCD module and emits a TODO that the
# operator team installs the keyvault operator manually (or via a
# kustomize-driven helm wrapper) until the module lands.

terraform {
  required_providers {
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

data "terraform_remote_state" "dc_controlplane" {
  backend = "local"
  config  = { path = "../05-dc-controlplane/terraform.tfstate" }
}

locals {
  ocd_ref         = "v0.8.2"
  dcapi_apiserver = "${data.terraform_remote_state.bootstrap.outputs.rancher_url}/k8s/clusters/${data.terraform_remote_state.dc_controlplane.outputs.dcapi_cluster_v3_id}"
}

provider "kubernetes" {
  host     = local.dcapi_apiserver
  token    = data.terraform_remote_state.rancher_auth.outputs.admin_token
  insecure = true
}

module "dc_webhook" {
  source = "github.com/wso2/open-cloud-datacenter//modules/management/dc-webhook?ref=${local.ocd_ref}"

  webhook_image            = var.dc_webhook_image
  harvester_kubeconfig_b64 = base64encode(file(var.harvester_kubeconfig_path))
  namespace                = "dc-webhook"
  replicas                 = 1
  log_level                = var.log_level
  webhook_domain           = var.webhook_domain
  ghcr_username            = var.ghcr_username
  ghcr_pat                 = var.ghcr_pat
}

# TODO(keyvault-operator): the keyvault operator does not ship as an OCD
# module yet. The manifests live at crds/keyvault/config/* in this repo.
# Two install paths until the module lands:
#
#   a) kubectl apply -k crds/keyvault/config/default (manual, but proven)
#
#   b) kubernetes_manifest resources here, one per CRD + RBAC + Deployment
#      — but kubernetes_manifest is fragile and order-sensitive (CRDs must
#      land before the manifests that reference them). Not recommended.
#
# Once modules/management/keyvault-operator lands, this layer will gain
# its module "keyvault_operator" { ... } block.
