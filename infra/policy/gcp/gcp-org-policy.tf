# GCP guardrails — Organization Policy constraints at the org/folder (doc 04 §4).
# Preventive: no external IPs, no public buckets, region lock, no default network.

terraform {
  required_providers {
    google = { source = "hashicorp/google", version = "~> 5.0" }
  }
}

variable "org_id" {
  description = "GCP organization id (or folder id to scope narrower)."
  type        = string
}

resource "google_org_policy_policy" "no_external_ip" {
  name   = "organizations/${var.org_id}/policies/compute.vmExternalIpAccess"
  parent = "organizations/${var.org_id}"
  spec {
    rules { deny_all = "TRUE" }
  }
}

resource "google_org_policy_policy" "storage_public_access_prevention" {
  name   = "organizations/${var.org_id}/policies/storage.publicAccessPrevention"
  parent = "organizations/${var.org_id}"
  spec {
    rules { enforce = "TRUE" }
  }
}

resource "google_org_policy_policy" "skip_default_network" {
  name   = "organizations/${var.org_id}/policies/compute.skipDefaultNetworkCreation"
  parent = "organizations/${var.org_id}"
  spec {
    rules { enforce = "TRUE" }
  }
}

resource "google_org_policy_policy" "resource_locations" {
  name   = "organizations/${var.org_id}/policies/gcp.resourceLocations"
  parent = "organizations/${var.org_id}"
  spec {
    rules {
      values { allowed_values = ["in:europe-west1-locations"] }
    }
  }
}
