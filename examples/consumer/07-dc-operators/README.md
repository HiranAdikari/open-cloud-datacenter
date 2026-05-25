# 07-dc-operators

Installs the managed-service operators on the dcapi-controlplane cluster.

**Wraps:** `modules/management/dc-webhook` (admission webhook supporting
dc-api's tenant isolation).

**TODO:** the keyvault operator does NOT yet ship as an OCD module. Its
manifests live at `crds/keyvault/config/*` in this repo. Until
`modules/management/keyvault-operator` lands, install it manually:

```bash
kubectl --kubeconfig <dcapi-kubeconfig> apply -k crds/keyvault/config/default
```

**Reads from terraform.tfvars:** `harvester_kubeconfig_path`,
`dc_webhook_image`, `webhook_domain`, `log_level`, `ghcr_username`,
`ghcr_pat`.

**Reads from upstream layers:** `01-bootstrap` (rancher_url),
`02-rancher-auth` (admin_token), `05-dc-controlplane`
(dcapi_cluster_v3_id — to build the kubeconfig the kubernetes provider
uses).

**Outputs:** `dc_webhook_namespace`.

**Readiness gate (wrapper):** none — operators self-report health via
Deployment probes.

Apply time: 1–2 minutes.
