terraform {
  required_version = ">= 1.6"

  # Local state by default. For production, uncomment + edit:
  #
  # backend "s3" {
  #   bucket         = "my-cloud-state"
  #   key            = "02-rancher-auth/terraform.tfstate"
  #   region         = "ap-southeast-1"
  #   encrypt        = true
  #   dynamodb_table = "my-cloud-state-locks"
  # }
}
