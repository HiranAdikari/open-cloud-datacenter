# dc-ms-operators

Umbrella Terraform module that deploys the DC managed-service
operators that `dc-api` dispatches custom resources to. Today: just
`keyvault`. Future: `postgres`, `redis`, `registry`, etc.

## When to use this module

| Consumer's situation | What to do |
|---|---|
| Runs `dc-api` + `cloudui` (the full DC control plane) | **Call this umbrella module.** Every managed-service operator that dc-api can dispatch CRs to must be installed, otherwise tenant operations on those services fail with "no controller". |
| Wants only one operator on their Harvester cluster (no dc-api) | Call a single sub-module directly, e.g. `source = ".../dc-ms-operators/keyvault"`. Skip the umbrella's input surface. |

## Inputs (umbrella)

| Variable | Type | Default | Notes |
|---|---|---|---|
| `enable_keyvault` | bool | `true` | Toggle the keyvault sub-module |
| `keyvault_image` | string | `ghcr.io/wso2/keyvault-operator` | Image, no tag |
| `keyvault_image_tag` | string | `v0.0.1` | Pinned tag |
| `keyvault_namespace` | string | `keyvault-system` | |
| `keyvault_enable_metrics_network_policy` | bool | `false` | Optional NetworkPolicy |
| `keyvault_enable_prometheus_servicemonitor` | bool | `false` | Requires Prometheus Operator on the cluster |
| `keyvault_enable_cert_manager_metrics` | bool | `false` | Requires cert-manager on the cluster |
| `ghcr_username` | string | `null` | Skip when operator images are public |
| `ghcr_pat` | string (sensitive) | `null` | Same |

## Outputs

| Output | Notes |
|---|---|
| `keyvault_namespace` | Null when `enable_keyvault = false` |
| `keyvault_deployment_name` | Same |
| `keyvault_image` | Same |

## Provider config

The umbrella declares no provider config. The caller supplies a
`kubernetes` provider — usually pointing at the **Harvester host
cluster** (these operators run alongside the OpenBao instances /
managed-service workloads they manage, not on dcapi-controlplane).

```hcl
provider "kubernetes" {
  config_path = var.harvester_kubeconfig_path
}

module "dc_ms_operators" {
  source = "../modules/open-cloud-datacenter/modules/management/dc-ms-operators"

  providers = {
    kubernetes = kubernetes
  }

  # Toggle each operator your consumer needs. For full DC consumers,
  # leave all enable_* at their `true` defaults.
  keyvault_image_tag = "v0.0.1"

  # Optional ghcr auth (omit if images are public)
  ghcr_username = var.ghcr_username
  ghcr_pat      = var.ghcr_pat
}
```

## Adding a new operator

1. Create `<name>/` sub-directory under `dc-ms-operators/` mirroring
   the `keyvault/` layout (variables.tf with `<prefix>_*` vars,
   main.tf with typed resources, outputs.tf, versions.tf,
   README.md, optional `crds/`).
2. Add `enable_<name>` + `<name>_*` vars to this umbrella's
   `variables.tf`.
3. Add a `module "<name>"` block in this umbrella's `main.tf` with
   `count = var.enable_<name> ? 1 : 0`.
4. Add pass-through outputs in this umbrella's `outputs.tf`.
5. Document the new operator's role in `dc-api` in this README's
   "When to use" section.

## Composition with other OCD modules

| Module | Composition |
|---|---|
| `harvester-integration` | Independent. Both target the Harvester cluster but operate on different namespaces. `harvester-integration` is the prerequisite (provisions Rancher cloud cred + namespace-credential-provisioner); `dc-ms-operators` runs on top of an already-integrated Harvester cluster. |
| `dc-controlplane-services` | Independent and runs on a different cluster (dcapi-controlplane). `dc-api` there dispatches CRs to the operators deployed here. |
| `dc-webhook` | Same cluster (Harvester). Bundled in the same consumer layer typically (the `dc-operators` layer in each environment). |
