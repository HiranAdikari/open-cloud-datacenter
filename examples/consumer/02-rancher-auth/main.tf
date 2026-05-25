# Layer 02: Rancher Auth
#
# Sets the permanent Rancher admin password and emits the API token every
# downstream layer needs. Kept separate from 01-bootstrap because
# rancher2_bootstrap can only run after Rancher is reachable — the wrapper's
# wait_after for 01 polls /v3/ping before this layer starts.

terraform {
  required_providers {
    rancher2 = { source = "rancher/rancher2", version = "~> 6.0" }
  }
}

data "terraform_remote_state" "bootstrap" {
  backend = "local"
  config = {
    path = "../01-bootstrap/terraform.tfstate"
  }
}

provider "rancher2" {
  alias     = "bootstrap"
  api_url   = data.terraform_remote_state.bootstrap.outputs.rancher_url
  bootstrap = true
  insecure  = true
}

resource "rancher2_bootstrap" "admin" {
  provider = rancher2.bootstrap

  # For greenfield: bootstrap_password is what Helm set in 01-bootstrap.
  # For brownfield (reapply after permanent password was already set):
  # bootstrap_password can be empty; coalesce falls back to rancher_admin_password.
  initial_password = coalesce(var.bootstrap_password, var.rancher_admin_password)
  password         = var.rancher_admin_password
}
