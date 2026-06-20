# Org-level resources — ADC supplies credentials + quota project.
# Apply needs roles/orgpolicy.policyAdmin on the org for the caller.
provider "google" {
  user_project_override = true
  billing_project       = var.quota_project
}

variable "quota_project" {
  type        = string
  default     = "mini-cloud-499820"
  description = "Project used for API quota/billing when calling org-level APIs."
}
