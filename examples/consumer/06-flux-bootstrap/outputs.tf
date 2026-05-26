output "flux_deploy_key_fingerprint" {
  description = "SSH fingerprint of the deploy key Flux uses to read + write the operator's fork. For auditing."
  value       = trimspace(tls_private_key.flux.public_key_fingerprint_sha256)
}

output "flux_namespace" {
  description = "Kubernetes namespace Flux's controllers run in."
  value       = "flux-system"
}

output "flux_cluster_path" {
  description = "Path inside the fork Flux's root Kustomization watches."
  value       = "flux/clusters/${var.env_name}"
}
