terraform {
  required_version = ">= 1.5"

  required_providers {
    harvester = {
      source  = "harvester/harvester"
      version = "~> 1.7"
    }
    rancher2 = {
      source  = "rancher/rancher2"
      version = "~> 13.1"
    }
    vyos = {
      source  = "thomasfinstad/vyos-rolling"
      version = "~> 19.1"
    }
  }
}
