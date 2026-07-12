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
  description = "Enable lakehouse (managed folders, Iceberg runtime catalog + namespaces, consumer IAM)."
}

variable "datasets" {
  type = map(object({
    description = optional(string, "")
    feeders     = optional(list(string), []) # SA emails: objectAdmin on this dataset's folder + biglake.editor on its namespace
    consumers   = optional(list(string), []) # principals with biglake.viewer on THIS namespace only
  }))
  default     = {}
  description = "Datasets: managed folder + Iceberg namespace each. Key = dataset name, value = { description, feeders, consumers }."
}

# Open-engine consumers (Spark/Trino/Flink/PyIceberg) granted read access to
# EVERY dataset via project-level roles/biglake.viewer. For per-dataset access
# use datasets[*].consumers instead. No direct GCS IAM either way — the Iceberg
# catalog vends downscoped GCS credentials. Members use IAM syntax, e.g.
# "user:a@example.com", "group:analysts@example.com", "serviceAccount:sa@proj.iam...".
variable "iceberg_consumers" {
  type        = list(string)
  default     = []
  description = "Principals granted project-level roles/biglake.viewer (read ALL datasets)."
}

# PoC default: feeders/consumers charge this project as REST-catalog quota
# project (serviceusage.serviceUsageConsumer grant). Set false in prod and have
# callers use their own project as quota project instead.
variable "grant_quota_project_access" {
  type        = bool
  default     = true
  description = "Grant feeders/consumers serviceusage.serviceUsageConsumer so x-goog-user-project can name this project."
}
