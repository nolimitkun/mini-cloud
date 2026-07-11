variable "spoke_project_id" {
  type    = string
  default = "mini-cloud-lakehouse"
}

variable "billing_account" {
  type = string
}

variable "org_id" {
  type        = string
  description = "GCP organization id (required — Shared VPC needs both projects in an org)."
}

variable "create_project" {
  type    = bool
  default = true
}

variable "region" {
  type    = string
  default = "europe-west1"
}

variable "zone" {
  type    = string
  default = "europe-west1-b"
}

variable "spoke_cidr" {
  type        = string
  default     = "10.48.16.0/24"
  description = "Spoke workload subnet, created in the HOST (hub) VPC."
}

variable "host_project_id" {
  type        = string
  description = "Shared VPC host project (the hub)."
}

variable "host_network_name" {
  type        = string
  description = "Hub VPC name (host network) to create the spoke subnet in."
}

variable "storage_bucket_name" {
  type        = string
  description = "Name for the spoke's private GCS data bucket (must be globally unique)."
}

# --- Lakehouse ---

variable "enable_lakehouse" {
  type        = bool
  default     = false
  description = "Enable lakehouse (Managed Folders, BigLake connection, BigQuery dataset, Iceberg runtime catalog)."
}

variable "datasets" {
  type = map(object({
    description = optional(string, "")
    feeders     = optional(list(string), []) # SA emails with objectAdmin on this dataset
  }))
  default     = {}
  description = "Datasets to create as managed folders. Key = dataset name, value = { description, feeders }."
}

# Open-engine consumers (Spark/Trino/Flink/PyIceberg) granted read access to the
# runtime catalog via roles/biglake.viewer. No direct GCS IAM — the Iceberg
# catalog vends downscoped GCS credentials. Members use IAM syntax, e.g.
# "user:a@example.com", "group:analysts@example.com", "serviceAccount:sa@proj.iam...".
variable "iceberg_consumers" {
  type        = list(string)
  default     = []
  description = "Principals granted roles/biglake.viewer to read via the Iceberg runtime catalog."
}
