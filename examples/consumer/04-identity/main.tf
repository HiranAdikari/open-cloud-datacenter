# Layer 04: Identity
#
# Creates an OIDC application on the IdP (Asgardeo by default; swap the
# provider module for azure-ad or roll your own preset) and wires Rancher
# to use it for SSO. Calls
#   modules/identity/providers/asgardeo  → registers the OIDC app on the IdP
#   modules/identity/rancher-oidc        → configures Rancher's generic-oidc auth provider
#
# NOTE: This layer ONLY creates the Rancher-SSO application. The dc-api
# BFF (cloud-ui-bff) and dcctl OIDC clients are not created here — OCD does
# not (yet) ship a generic IdP-app module for them. Create those manually
# on your IdP per docs/prerequisites.md and put their client_id / secret
# into terraform.tfvars; 06-dc-controlplane-services reads them from there.

terraform {
  required_providers {
    asgardeo = { source = "hiranadikari/asgardeo", version = "~> 0.1" }
    rancher2 = { source = "rancher/rancher2", version = "~> 6.0" }
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

provider "asgardeo" {
  org_name      = var.asgardeo_org_name
  client_id     = var.asgardeo_management_client_id
  client_secret = var.asgardeo_management_client_secret
}

provider "rancher2" {
  api_url   = data.terraform_remote_state.bootstrap.outputs.rancher_url
  token_key = data.terraform_remote_state.rancher_auth.outputs.admin_token
  insecure  = true
}

locals {
  ocd_ref      = "v0.8.2"
  rancher_url  = data.terraform_remote_state.bootstrap.outputs.rancher_url
}

# Step 1 — register Rancher as an OIDC application on the IdP.
module "idp" {
  source = "github.com/wso2/open-cloud-datacenter//modules/identity/providers/asgardeo?ref=${local.ocd_ref}"

  org_name             = var.asgardeo_org_name
  app_name             = var.asgardeo_app_name
  description          = "Rancher Manager SSO via Asgardeo. Managed by Terraform."
  access_url           = "${local.rancher_url}/dashboard"
  callback_urls        = ["${local.rancher_url}/verify-auth"]
  allowed_origins      = [local.rancher_url]
  logout_redirect_urls = ["${local.rancher_url}/dashboard/auth/logout"]
  skip_consent         = var.skip_consent
}

# Step 2 — configure Rancher's generic OIDC provider against that app.
module "rancher_oidc" {
  source = "github.com/wso2/open-cloud-datacenter//modules/identity/rancher-oidc?ref=${local.ocd_ref}"

  client_id            = module.idp.client_id
  client_secret        = module.idp.client_secret
  issuer_url           = module.idp.issuer_url
  auth_endpoint        = module.idp.auth_endpoint
  token_endpoint       = module.idp.token_endpoint
  jwks_url             = module.idp.jwks_url
  rancher_callback_url = "${local.rancher_url}/verify-auth"
}
