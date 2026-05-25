terraform {
  required_version = ">= 1.6"

  # Local state by default — produces ./terraform.tfstate next to main.tf.
  # For production (multi-operator, durable, locked), uncomment the S3 block,
  # pre-create the bucket + DynamoDB lock table, and fill in your values.
  #
  # backend "s3" {
  #   bucket         = "my-cloud-state"
  #   key            = "01-bootstrap/terraform.tfstate"
  #   region         = "ap-southeast-1"
  #   encrypt        = true
  #   dynamodb_table = "my-cloud-state-locks"
  # }
}
