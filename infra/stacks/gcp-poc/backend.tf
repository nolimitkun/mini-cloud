# Remote state in GCS (versioned bucket in the hub project). Enables durable
# state + a CI diagram job. Migrated from local state via `terraform init -migrate-state`.
terraform {
  backend "gcs" {
    bucket = "mini-cloud-499820-tfstate"
    prefix = "stacks/gcp-poc"
  }
}
