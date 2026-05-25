variable "harvester_kubeconfig_path" {
  description = "Path to the Harvester HCI kubeconfig on the operator's workstation."
  type        = string
}

variable "harvester_cluster_name" {
  description = "Name Harvester appears under inside Rancher after registration."
  type        = string
  default     = "harvester"
}
