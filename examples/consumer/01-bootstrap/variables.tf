variable "harvester_kubeconfig_path" {
  description = "Path to the Harvester HCI kubeconfig on the operator's workstation."
  type        = string
}

variable "harvester_namespace" {
  description = "Harvester namespace the Rancher VM lives in."
  type        = string
  default     = "rancher-infra"
}

variable "node_count" {
  description = "Number of Rancher VMs. 1 = dev, 3 = HA (kube-vip fronted)."
  type        = number
  default     = 1
}

variable "image_url" {
  description = "URL of the Ubuntu cloud image to clone for the Rancher VM. Downloaded into Harvester on first apply."
  type        = string
}

variable "vm_password" {
  description = "Console/SSH password for the Rancher VM user."
  type        = string
  sensitive   = true
}

variable "network_type" {
  description = "Network attachment type — vlan | pod | bridge."
  type        = string
  default     = "vlan"
}

variable "network_name" {
  description = "Harvester NAD reference (namespace/name) the Rancher VM joins."
  type        = string
}

variable "rancher_hostname" {
  description = "FQDN Rancher will serve at. Must resolve to the LB IP allocated from ippool_*."
  type        = string
}

variable "bootstrap_password" {
  description = "Initial admin password Helm sets during Rancher install. Replaced by 02-rancher-auth."
  type        = string
  sensitive   = true
}

variable "rke2_version" {
  description = "RKE2 version for the Rancher server cluster."
  type        = string
  default     = "v1.33.10+rke2r3"
}

variable "rancher_version" {
  description = "Rancher Helm chart version."
  type        = string
  default     = "v2.12.1"
}

variable "tls_source" {
  description = "Rancher TLS source — rancher (self-signed) | letsEncrypt | secret."
  type        = string
  default     = "rancher"
}

variable "create_lb" {
  description = "Whether the bootstrap creates the LoadBalancer + IPPool for Rancher."
  type        = bool
  default     = true
}

variable "ippool_subnet" {
  description = "CIDR of the management VLAN."
  type        = string
}

variable "ippool_gateway" {
  description = "Gateway IP for the management VLAN."
  type        = string
}

variable "ippool_start" {
  description = "First IP in the bootstrap LB pool."
  type        = string
}

variable "ippool_end" {
  description = "Last IP in the bootstrap LB pool."
  type        = string
}

variable "ippool_network_name" {
  description = "Harvester NAD reference (namespace/name) the IPPool is scoped to."
  type        = string
}

variable "static_rancher_ip" {
  description = "Specific IP to pin Rancher's LB to (must be inside ippool_start..ippool_end)."
  type        = string
}
