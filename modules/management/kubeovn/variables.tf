variable "manage_kubeovn_install" {
  description = "When true (the default), this module installs KubeOVN via the upstream Helm chart. Set false when KubeOVN is already installed by another mechanism — Harvester's built-in `kubeovn-operator` Addon, a prior manual `helm install`, or an admin-supplied install. The ProviderNetwork + VLAN + Subnet are still managed by this module either way (they're the artifacts dc-api depends on; their lifecycle is independent of who installed the controller). Namespace separation does NOT resolve the conflict: KubeOVN's CRDs are cluster-scoped and the OVN central database is a singleton — two installs will fight regardless of where their pods live."
  type        = bool
  default     = true
}

variable "chart_version" {
  description = "kube-ovn Helm chart version. Pinned to a release tested with our VpcDns + bridge-mediation pattern. Ignored when manage_kubeovn_install = false."
  type        = string
  default     = "v1.15.4"
}

variable "extra_values" {
  description = "Extra YAML values appended to the kube-ovn HelmRelease (after the module's defaults). Use for site-specific overrides without editing the module."
  type        = string
  default     = ""
}

# ── External ProviderNetwork ─────────────────────────────────────────────────

variable "external_provider_network_name" {
  description = "Name of the kube-ovn ProviderNetwork CR for the external (SNAT/EIP) network."
  type        = string
  default     = "ext-vlan-0"
}

variable "external_bridge" {
  description = "Host Linux bridge the ProviderNetwork attaches to. `mgmt-br` is Harvester's built-in management bridge (auto-created on every node)."
  type        = string
  default     = "mgmt-br"
}

variable "external_vlan_name" {
  description = "Name of the kube-ovn Vlan CR for the external network."
  type        = string
  default     = "ext-vlan-0"
}

variable "external_vlan_id" {
  description = "VLAN ID for the external network. 0 = untagged (i.e. the management VLAN itself). Use a dedicated tagged VLAN in production to isolate VPC SNAT traffic from management traffic (see F22)."
  type        = number
  default     = 0
}

variable "external_cidr" {
  description = "CIDR of the external network. dc-api allocates VPC EIPs from this range. Same as the management VLAN when external_vlan_id = 0."
  type        = string
}

variable "external_gateway" {
  description = "Upstream gateway IP for the external network."
  type        = string
}

variable "external_excluded_ips" {
  description = "IPs already in use on the external network that kube-ovn must not allocate (Harvester host node IPs, Rancher LB VIP, dc-api ingress VIP, dcapi-controlplane apiserver VIP, anything else pinned on this VLAN)."
  type        = list(string)
  default     = []
}
