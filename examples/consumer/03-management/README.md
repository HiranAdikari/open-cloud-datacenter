# 03-management

Registers the Harvester HCI cluster into Rancher so downstream layers can
provision RKE2 clusters on top of it. Calls
[`modules/management/harvester-integration`](../../../modules/management/harvester-integration/).

**Reads from terraform.tfvars:** `harvester_kubeconfig_path`,
`harvester_cluster_name` (optional).

**Reads from upstream layers:** `01-bootstrap` (rancher hostname + LB IP),
`02-rancher-auth` (admin token).

**Outputs:** `harvester_cluster_id`, `harvester_cluster_name`.

**Readiness gate (wrapper):** none — the underlying TF resources block on
their own server-side reconcile (Rancher registers the Harvester cluster
synchronously).

**Future expansion:** add module calls for `modules/management/networking`
(curate Harvester VLAN NADs the platform uses), `modules/management/storage`
(register OS images into Harvester for tenant VM provisioning),
`modules/management/rbac` (create base Rancher projects + namespaces),
`modules/management/cluster-roles` (custom Rancher role templates),
`modules/management/tenant-space` (per-tenant project + namespace +
quotas). Stub layer kept minimal so the install path is reachable end-to-end;
add these incrementally as your platform grows.

Apply time: 1–2 minutes.
