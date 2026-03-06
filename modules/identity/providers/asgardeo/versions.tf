terraform {
  required_version = ">= 1.3"
  required_providers {
    asgardeo = {
      source = "asgardeo/asgardeo"
      # Version constraint is informational while dev_overrides is active.
      # Remove once the provider is published to the Terraform Registry.
      version = "~> 0.1"
    }
  }
}
