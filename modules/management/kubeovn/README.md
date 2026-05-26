# modules/management/kubeovn

Installs KubeOVN on a Harvester host cluster and bootstraps the external
ProviderNetwork that dc-api allocates VPC EIPs from. Call this from the
consumer's `02-management` (or equivalent) layer alongside `harvester-integration`.

## What it installs

1. **kube-ovn** Helm release (chart at `var.chart_version`, default `v1.15.4`)
   in the `kube-ovn` namespace.
2. **ProviderNetwork** named `ext-vlan-0` (configurable) bound to host bridge
   `mgmt-br` (configurable).
3. **Vlan** with ID 0 (untagged — i.e. the management VLAN itself).
4. **Subnet** `ovn-vpc-external-network` carved from `var.external_cidr`,
   with the operator's already-used IPs in `excludeIps`.

The NetworkAttachmentDefinition (NAD) wrapping the subnet is created by
dc-api at startup, not by this module.

## You can only have ONE KubeOVN per cluster

The default is to install upstream KubeOVN directly (Helm, `v1.15.4`).
That conflicts with two other paths people often choose:

| Path | Where it lives | Version |
|---|---|---|
| **This module** (default) | `kube-ovn` namespace, raw Helm release | `v1.15.4` (overridable) |
| **Harvester built-in Addon** | Operator in `kubeovn-system`; pods in `kube-ovn` | `v1.14.10`, with `enable-lb: true` (incompatible with our VpcDns pattern) |
| **Manual install** | Wherever the admin ran `helm install` | Whatever they pinned |

A namespace prefix wouldn't help — KubeOVN's CRDs are cluster-scoped, the
OVN central database is a singleton (raft cluster named `ovn-central`,
collides on PVs + Service names), and the CNI binary lives at one path
on each node. Two installs always fight at one of those layers.

If KubeOVN is **already installed** by another mechanism, set:

```hcl
module "kubeovn" {
  source = "..."
  manage_kubeovn_install = false   # skip the Helm release + namespace
  # ...
}
```

The module will skip the install but still create the ProviderNetwork +
VLAN + Subnet (those are stable artifacts dc-api needs regardless of
who installed the controller).

If the **Harvester Addon** is enabled and you want this module's
standalone install instead, disable it first:

```bash
kubectl --context=<harvester-context> patch addon kubeovn-operator \
    -n kube-system --type=merge -p '{"spec":{"enabled":false}}'
# (also delete any pods the Addon created)
```

## Example caller

```hcl
provider "kubernetes" {
  alias       = "harvester"
  config_path = var.harvester_kubeconfig_path
}

provider "helm" {
  alias = "harvester"
  kubernetes {
    config_path = var.harvester_kubeconfig_path
  }
}

module "kubeovn" {
  source = "github.com/wso2/open-cloud-datacenter//modules/management/kubeovn?ref=vX.Y.Z"
  providers = {
    kubernetes = kubernetes.harvester
    helm       = helm.harvester
  }

  external_cidr          = "192.168.10.0/24"
  external_gateway       = "192.168.10.254"
  external_excluded_ips  = [
    "192.168.10.6",   # Harvester host VIP
    "192.168.10.35",  # Rancher LB
    "192.168.10.37",  # dc-api ingress
    "192.168.10.36",  # dcapi-controlplane apiserver VIP
  ]
}
```

## Brownfield import (existing manual install)

For clusters where KubeOVN was already installed by hand (the lk-dev case)
the Helm release and the three CRs already exist. Import each before the
first apply so TF adopts them instead of replacing them:

```bash
terraform import 'module.kubeovn.helm_release.kube_ovn' kube-ovn/kube-ovn
terraform import 'module.kubeovn.kubernetes_manifest.provider_network_external' \
    'apiVersion=kubeovn.io/v1,kind=ProviderNetwork,name=ext-vlan-0'
terraform import 'module.kubeovn.kubernetes_manifest.vlan_external' \
    'apiVersion=kubeovn.io/v1,kind=Vlan,name=ext-vlan-0'
terraform import 'module.kubeovn.kubernetes_manifest.subnet_external' \
    'apiVersion=kubeovn.io/v1,kind=Subnet,name=ovn-vpc-external-network'
```
