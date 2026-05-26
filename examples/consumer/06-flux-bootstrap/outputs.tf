output "flux_namespace" {
  description = "Kubernetes namespace Flux's controllers run in."
  value       = "flux-system"
}

output "flux_cluster_path" {
  description = "Path inside the fork Flux's root Kustomization watches."
  value       = "flux/clusters/${var.env_name}"
}
