# 05-dc-controlplane

Provisions the `dcapi-controlplane` RKE2 cluster on Harvester via Rancher.
This is the substrate that hosts dc-api, cloud-ui, and managed-service
operators (layers 06 + 07). Calls
[`modules/management/dc-controlplane`](../../../modules/management/dc-controlplane/).

**Reads from terraform.tfvars:** `harvester_kubeconfig_path`,
`dcapi_cluster_name`, `dcapi_project_name`, `dcapi_kubernetes_version`,
`dcapi_node_count`, `dcapi_lb_range_start`/`end`, `lb_subnet`, `lb_gateway`.

**Reads from upstream layers:** `01-bootstrap` (rancher_url, vm_image_id),
`02-rancher-auth` (admin_token), `03-management` (harvester_cluster_id,
cloud_credential_id).

**Outputs:** `dcapi_cluster_id`, `dcapi_cluster_v3_id`, `dcapi_cluster_name`,
`dcapi_project_id`, `dcapi_kubeconfig_path` (Rancher-proxy kubeconfig
written to `.dcapi-kubeconfig`; gitignored).

**Readiness gate (wrapper):** `kubectl --kubeconfig=.dcapi-kubeconfig
wait --for=condition=Ready nodes --all --timeout=20m`.

Apply time: 10–15 minutes (Rancher provisions, RKE2 installs on every
node, nodes join + reach Ready).
