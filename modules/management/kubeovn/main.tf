# ─────────────────────────────────────────────────────────────────────────────
# KubeOVN — install + bootstrap the external ProviderNetwork
#
# dc-api manages KubeOVN Vpc / Subnet / VpcNatGateway / NAD resources at
# runtime against the Harvester host cluster's K8s API. For that to work,
# KubeOVN itself must be installed on Harvester, AND the external
# ProviderNetwork + VLAN + subnet that VPC EIPs are SNAT'd through must
# exist.
#
# This module:
#
#  1. Installs `kube-ovn` upstream Helm chart into the `kube-ovn` namespace.
#     Pinned default to a version known to work with our VpcDns + bridge
#     mediation pattern. Override `chart_version` to bump.
#
#  2. Creates a kube-ovn `ProviderNetwork` claiming `var.external_bridge`
#     as the external network. Default `mgmt-br` matches Harvester's
#     built-in management bridge on every node.
#
#  3. Creates a kube-ovn `Vlan` against that ProviderNetwork.
#
#  4. Creates the `ovn-vpc-external-network` subnet that dc-api allocates
#     tenant VPC EIPs from. The NAD referencing this subnet is created by
#     dc-api at startup (`CreateVPCExternalNetwork` in the kubeovn provider)
#     — not by this module.
#
# Provider: requires a `kubernetes` provider aliased at the Harvester host
# cluster (NOT a downstream RKE2 cluster). Pass it via `providers = {
#   kubernetes = kubernetes.harvester, helm = helm.harvester }`.
# ─────────────────────────────────────────────────────────────────────────────

terraform {
  required_version = ">= 1.7"
  required_providers {
    kubernetes = { source = "hashicorp/kubernetes", version = "~> 2.30" }
    helm       = { source = "hashicorp/helm",       version = "~> 2.13" }
  }
}

resource "kubernetes_namespace" "kubeovn" {
  count = var.manage_kubeovn_install ? 1 : 0
  metadata {
    name = "kube-ovn"
  }
  lifecycle {
    ignore_changes = [metadata[0].annotations]
  }
}

resource "helm_release" "kube_ovn" {
  count      = var.manage_kubeovn_install ? 1 : 0
  name       = "kube-ovn"
  namespace  = kubernetes_namespace.kubeovn[0].metadata[0].name
  repository = "https://kubeovn.github.io/kube-ovn"
  chart      = "kube-ovn"
  version    = var.chart_version

  # Inline values. Most defaults are fine; the explicit overrides below
  # match what's running on Harvester today.
  values = [
    yamlencode({
      # Without --enable-lb we lose the VpcDns CRD pattern, but Harvester
      # already provides LoadBalancer Services via its own Harvester
      # cloud-provider on downstream clusters. dc-api's per-VPC CoreDNS
      # is what fills the VpcDns gap (see F20 in the dc-api repo).
      MASTER_NODES_LABEL = "node-role.kubernetes.io/control-plane"
    }),
    var.extra_values,
  ]

  # CRDs change between chart versions — let Helm replace them on upgrade
  # so kubectl-apply state stays in sync.
  replace          = false
  cleanup_on_fail  = true
  wait             = true
  timeout          = 600
  create_namespace = false
}

# ── External ProviderNetwork ─────────────────────────────────────────────────
# Claims var.external_bridge (default mgmt-br) as the external network
# kube-ovn uses for VPC SNAT/EIP traffic.
resource "kubernetes_manifest" "provider_network_external" {
  manifest = {
    apiVersion = "kubeovn.io/v1"
    kind       = "ProviderNetwork"
    metadata = {
      name = var.external_provider_network_name
    }
    spec = {
      defaultInterface = var.external_bridge
      # exchangeLinkName: false — Harvester nodes already have mgmt-br as a
      # Linux bridge; don't rename the physical interface.
      exchangeLinkName = false
    }
  }
  # Only block on the Helm release when we're the one installing it. When
  # manage_kubeovn_install = false, KubeOVN is expected to already be running.
  depends_on = [helm_release.kube_ovn]
}

# ── VLAN ─────────────────────────────────────────────────────────────────────
# VLAN ID 0 = untagged (the management VLAN itself). For an isolated SNAT
# VLAN (F22 in the dc-api repo), bump this and the corresponding Harvester
# vm-network NAD's VLAN ID together.
resource "kubernetes_manifest" "vlan_external" {
  manifest = {
    apiVersion = "kubeovn.io/v1"
    kind       = "Vlan"
    metadata = {
      name = var.external_vlan_name
    }
    spec = {
      id       = var.external_vlan_id
      provider = var.external_provider_network_name
    }
  }
  depends_on = [kubernetes_manifest.provider_network_external]
}

# ── Subnet (the ovn-vpc-external-network) ────────────────────────────────────
# dc-api allocates per-tenant VPC EIPs from this subnet at runtime via the
# kubeovn provisioner. The NAD that wraps this subnet is created by dc-api
# (so the consumer layer doesn't need to manage it).
resource "kubernetes_manifest" "subnet_external" {
  manifest = {
    apiVersion = "kubeovn.io/v1"
    kind       = "Subnet"
    metadata = {
      name = "ovn-vpc-external-network"
    }
    spec = {
      protocol   = "IPv4"
      cidrBlock  = var.external_cidr
      gateway    = var.external_gateway
      excludeIps = var.external_excluded_ips
      vlan       = kubernetes_manifest.vlan_external.manifest.metadata.name
      vpc        = "ovn-cluster"
      # KubeOVN reserves names like ovn-default for cluster-internal pods;
      # this subnet exists purely for external NAT.
      namespaces = []
    }
  }
  depends_on = [kubernetes_manifest.vlan_external]
}
