terraform {
  required_version = ">= 1.7"
  required_providers {
    # Sub-modules need kubernetes ~> 2.30. Caller's kubernetes provider
    # is passed through via the `providers` block.
    kubernetes = {
      source = "hashicorp/kubernetes"
    }
  }
}
