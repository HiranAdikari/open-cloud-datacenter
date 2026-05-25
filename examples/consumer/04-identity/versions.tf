terraform {
  required_version = ">= 1.6"

  # backend "s3" { bucket = "my-cloud-state"; key = "04-identity/terraform.tfstate"; region = "ap-southeast-1"; encrypt = true; dynamodb_table = "my-cloud-state-locks" }
}
