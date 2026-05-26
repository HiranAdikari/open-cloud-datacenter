terraform {
  required_version = ">= 1.7"

  # backend "s3" {
  #   bucket         = "my-cloud-state"
  #   key            = "06-flux-bootstrap/terraform.tfstate"
  #   region         = "ap-southeast-1"
  #   encrypt        = true
  #   dynamodb_table = "my-cloud-state-locks"
  # }
}
