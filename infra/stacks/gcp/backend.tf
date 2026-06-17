# Remote state for the GCP stack. Fill the TODO values, then `terraform init`.
# Use a GCS bucket in the management/host project (versioned, uniform access).
terraform {
  backend "gcs" {
    bucket = "TODO-hybrid-cloud-tfstate" # TODO: pre-created, versioned bucket
    prefix = "stacks/gcp"
  }
}
