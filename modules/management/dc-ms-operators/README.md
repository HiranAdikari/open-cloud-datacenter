# dc-ms-operators

Deploys managed-service operator controllers onto a Harvester RKE2 cluster.
Today this contains the **keyvault-operator** (OpenBao HA orchestrator).
DB, cache, and registry operators are added here as additional resource
blocks when those operators are ready — the module grows inline before
any sub-module extraction.

## What it deploys (keyvault-operator)

| Resource | Name | Kind |
|---|---|---|
| Namespace | `keyvault-system` (var) | `Namespace` |
| CRD | `keyvaultbackends.keyvault.opencloud.wso2.com` | `CustomResourceDefinition` |
| CRD | `keyvaultinstances.keyvault.opencloud.wso2.com` | `CustomResourceDefinition` |
| ServiceAccount | `keyvault-controller-manager` | `ServiceAccount` |
| Role | `keyvault-leader-election-role` | `Role` (namespaced) |
| RoleBinding | `keyvault-leader-election-rolebinding` | `RoleBinding` (namespaced) |
| ClusterRole | `keyvault-manager-role` | `ClusterRole` |
| ClusterRoleBinding | `keyvault-manager-rolebinding` | `ClusterRoleBinding` |
| ClusterRole | `keyvault-metrics-auth-role` | `ClusterRole` |
| ClusterRoleBinding | `keyvault-metrics-auth-rolebinding` | `ClusterRoleBinding` |
| ClusterRole | `keyvault-metrics-reader` | `ClusterRole` |
| Deployment | `keyvault-controller-manager` | `Deployment` |
| Service | `keyvault-operator-metrics` | `Service` (port 8443) |
| Secret (optional) | `ghcr-pull-secret` | `kubernetes.io/dockerconfigjson` |

CRD files live under `crds/` inside this module and are loaded at plan time
via `file()`. They must be kept in sync with the operator image version.

## Prerequisites

- Harvester RKE2 cluster running Kubernetes >= 1.28.
- Pod Security Admission: the `keyvault-system` namespace is compatible with
  `enforce=restricted` (controller runs as non-root, drops ALL capabilities,
  read-only root filesystem, `seccompProfile: RuntimeDefault`). No label is
  added to the namespace by this module — the caller sets the PSA level.
- Longhorn (or another CSI) available on the cluster. The controller creates
  per-tenant `KeyVaultBackend` StatefulSets with PVCs; the storage class is
  specified on the `KeyVaultBackend` CR spec, not by this module.

## Usage

The caller creates a `kubernetes` provider pointing at the target cluster
and passes it via the `providers` block:

```hcl
provider "kubernetes" {
  alias       = "dcapi_cluster"
  config_path = "/path/to/harvester-rke2.yaml"
}

module "ms_operators" {
  source = "../modules/open-cloud-datacenter/modules/management/dc-ms-operators"

  providers = {
    kubernetes = kubernetes.dcapi_cluster
  }

  kv_image     = "ghcr.io/hiranadikari/keyvault-operator"
  kv_image_tag = "v0.1.0"
  ghcr_username = var.ghcr_username
  ghcr_pat      = var.ghcr_pat
}
```

## Inputs

| Name | Type | Default | Description |
|---|---|---|---|
| `kv_namespace` | `string` | `"keyvault-system"` | Namespace the keyvault-operator runs in |
| `kv_image` | `string` | `"ghcr.io/hiranadikari/keyvault-operator"` | Image registry path, no tag |
| `kv_image_tag` | `string` | `"v0.0.1"` | Pinned image tag |
| `ghcr_username` | `string` | `""` | GHCR username; leave empty to skip pull secret |
| `ghcr_pat` | `string` (sensitive) | `""` | GHCR PAT; leave empty to skip pull secret |

## Outputs

| Name | Description |
|---|---|
| `kv_namespace` | Namespace the controller is deployed into |
| `kv_deployment_name` | Name of the controller-manager Deployment |
| `kv_image` | Fully-qualified `image:tag` used by the Deployment |

## Image lifecycle

The Deployment carries `lifecycle { ignore_changes = [... container[0].image] }`.
This means TF seeds the initial image on first apply, then CI owns rolling it
forward via `kubectl set image`. To force TF to pin a specific tag again,
remove the resource from state and re-apply, or explicitly bump `kv_image_tag`
after removing the lifecycle block temporarily.

## Composition with upstream layers

This module sits downstream of `harvester-integration` (which registers the
cluster with Rancher) and `dc-controlplane` (which creates the RKE2 cluster).
The consumer layer wires the kubernetes provider from the cluster's kubeconfig
output, exactly as `dc-controlplane-services` does today. Consumer-layer
wiring is in `wso2-datacenter-project` (TBD).

## Deviations from source YAML

| YAML | This module | Reason |
|---|---|---|
| `managed-by: kustomize` | `managed-by: terraform` | Reflects actual deployment tool |
| `imagePullSecrets` always present | Conditional on `ghcr_username`+`ghcr_pat` | Allows public-image or cluster-level-credential deployments without a dummy secret |
| Image `ghcr.io/wso2/keyvault-operator:v0.9.0` | `var.kv_image:var.kv_image_tag` | Caller-controlled; not pinned to the Flux automation placeholder tag |
