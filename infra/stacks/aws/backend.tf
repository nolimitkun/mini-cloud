# Remote state for the AWS stack. Fill the TODO values, then `terraform init`.
# Use a bucket + lock table in the network/management account (not a workload account).
terraform {
  backend "s3" {
    bucket         = "TODO-hybrid-cloud-tfstate"   # TODO: pre-created, versioned, encrypted
    key            = "stacks/aws/terraform.tfstate"
    region         = "eu-west-1"
    dynamodb_table = "TODO-hybrid-cloud-tflock"      # TODO: pre-created lock table
    encrypt        = true
  }
}
