output "dcapi_cluster_id" {
  description = "Rancher's provisioning.cattle.io cluster ID (fleet-default/<name>) for the dcapi cluster."
  value       = module.dc_controlplane.cluster_id
}

output "dcapi_cluster_v3_id" {
  description = "Legacy v3 cluster ID (c-m-xxxxx). Combine with rancher_url to form the kubeconfig proxy URL."
  value       = module.dc_controlplane.cluster_v3_id
}

output "dcapi_cluster_name" {
  description = "Cluster display name."
  value       = module.dc_controlplane.cluster_name
}

output "dcapi_project_id" {
  description = "Rancher project ID for the dc-api project on the dcapi cluster."
  value       = module.dc_controlplane.project_id
}

# Helper output the wrapper's readiness gate looks for. The wrapper will
# kubectl-wait nodes Ready against this kubeconfig path. We write the
# Rancher-proxy kubeconfig to a temp file so kubectl can consume it.
resource "local_file" "dcapi_kubeconfig" {
  filename        = "${path.module}/.dcapi-kubeconfig"
  file_permission = "0600"
  content = yamlencode({
    apiVersion = "v1"
    kind       = "Config"
    clusters = [{
      name = module.dc_controlplane.cluster_name
      cluster = {
        server                     = "${data.terraform_remote_state.bootstrap.outputs.rancher_url}/k8s/clusters/${module.dc_controlplane.cluster_v3_id}"
        insecure-skip-tls-verify = true
      }
    }]
    users = [{
      name = "admin"
      user = { token = data.terraform_remote_state.rancher_auth.outputs.admin_token }
    }]
    contexts = [{
      name    = module.dc_controlplane.cluster_name
      context = { cluster = module.dc_controlplane.cluster_name, user = "admin" }
    }]
    current-context = module.dc_controlplane.cluster_name
  })
}

output "dcapi_kubeconfig_path" {
  description = "Path to a Rancher-proxy kubeconfig the wrapper uses for kubectl-wait. .gitignored."
  value       = local_file.dcapi_kubeconfig.filename
}
