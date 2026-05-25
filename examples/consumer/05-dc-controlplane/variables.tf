variable "harvester_kubeconfig_path" {
  description = "Path to the Harvester kubeconfig."
  type        = string
}

variable "dcapi_cluster_name" {
  description = "RKE2 cluster name for the dcapi-controlplane."
  type        = string
  default     = "dcapi-controlplane-rke2"
}

variable "dcapi_project_name" {
  description = "Rancher project name + VM namespace for the dc-api control plane."
  type        = string
  default     = "dc-api"
}

variable "dcapi_kubernetes_version" {
  description = "RKE2 version for the dcapi-controlplane cluster."
  type        = string
  default     = "v1.33.10+rke2r3"
}

variable "dcapi_node_count" {
  description = "Number of nodes in the dcapi-controlplane. 1 = dev, 3 = HA (etcd quorum)."
  type        = number
  default     = 1
}

variable "dcapi_lb_range_start" {
  description = "First IP in the LoadBalancer VIP range for the dcapi cluster (apiserver + ingress). MUST NOT overlap with the 01-bootstrap pool."
  type        = string
}

variable "dcapi_lb_range_end" {
  description = "Last IP in the dcapi cluster's LB VIP range."
  type        = string
}

variable "lb_subnet" {
  description = "Subnet CIDR containing the LB VIP range (same management VLAN as 01-bootstrap)."
  type        = string
}

variable "lb_gateway" {
  description = "Default gateway for the LB VIP subnet."
  type        = string
}
