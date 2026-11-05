# Speech-to-Text (Chirp 3) and Text-to-Speech for on-prem callers, without a
# key file.
#
# The on-prem Kubernetes cluster signs service-account tokens; this pool trusts
# that cluster's public keys (uploaded as JWKS, since its issuer is not public)
# and lets one Kubernetes service account impersonate a Google SA that can only
# call the speech APIs. Traffic reaches the API through the PSC endpoint in the
# VPN module, not the internet.

terraform {
  required_providers {
    google = {
      source                = "hashicorp/google"
      version               = ">= 5.0, < 8.0"
      configuration_aliases = [google.hub_quota]
    }
  }
}

resource "google_project_service" "speech" {
  project            = var.project_id
  service            = "speech.googleapis.com"
  disable_on_destroy = false
}

# Text-to-Speech has no IAM permission of its own: any caller that may bill the
# project (serviceUsageConsumer, below) can synthesize.
resource "google_project_service" "tts" {
  project            = var.project_id
  service            = "texttospeech.googleapis.com"
  disable_on_destroy = false
}

# STS + IAM Credentials carry the token exchange and SA impersonation. IAM is
# for the pool and SA themselves: callers that bill this project (the CI plan
# job's SA) cannot even read them without it.
resource "google_project_service" "token_exchange" {
  for_each           = toset(["sts.googleapis.com", "iamcredentials.googleapis.com", "iam.googleapis.com"])
  project            = var.project_id
  service            = each.value
  disable_on_destroy = false
}

# The org restricts locations to europe-west1 (infra/policy/gcp), but Chirp 3
# only runs in the `us` and `eu` multi-regions. This project-level policy keeps
# the org's list and adds `eu` for the hub only, so audio stays in the EU and
# every other project keeps the region lock.
resource "google_org_policy_policy" "allow_eu" {
  provider = google.hub_quota
  name     = "projects/${var.project_id}/policies/gcp.resourceLocations"
  parent   = "projects/${var.project_id}"
  spec {
    inherit_from_parent = true
    rules {
      values { allowed_values = ["eu"] }
    }
  }
}

resource "google_service_account" "stt" {
  project      = var.project_id
  account_id   = var.service_account_id
  display_name = "Speech-to-Text caller (on-prem LiteLLM, via WIF)"
}

# speech.client covers recognize; serviceUsageConsumer because callers bill the
# project as quota project (x-goog-user-project).
resource "google_project_iam_member" "stt" {
  for_each = toset(["roles/speech.client", "roles/serviceusage.serviceUsageConsumer"])
  project  = var.project_id
  role     = each.value
  member   = "serviceAccount:${google_service_account.stt.email}"
}

resource "google_iam_workload_identity_pool" "k8s" {
  project                   = var.project_id
  workload_identity_pool_id = var.pool_id
  display_name              = "On-prem Kubernetes"
  description               = "Service-account tokens from the on-prem minikube cluster."
}

resource "google_iam_workload_identity_pool_provider" "k8s" {
  project                            = var.project_id
  workload_identity_pool_id          = google_iam_workload_identity_pool.k8s.workload_identity_pool_id
  workload_identity_pool_provider_id = var.provider_id
  display_name                       = "minikube"
  attribute_mapping = {
    "google.subject" = "assertion.sub"
  }
  # Only the gateway's service account; any other pod's token is rejected.
  attribute_condition = "assertion.sub == '${var.k8s_subject}'"
  oidc {
    issuer_uri = var.k8s_issuer
    jwks_json  = var.k8s_jwks
  }
}

resource "google_service_account_iam_member" "stt_wif" {
  service_account_id = google_service_account.stt.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principal://iam.googleapis.com/${google_iam_workload_identity_pool.k8s.name}/subject/${var.k8s_subject}"
}
