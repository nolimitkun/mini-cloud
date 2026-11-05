output "service_account_email" {
  value = google_service_account.stt.email
}

output "token_audience" {
  description = "Audience for the projected Kubernetes token."
  value       = "//iam.googleapis.com/${google_iam_workload_identity_pool_provider.k8s.name}"
}

# ADC external_account config for the gateway pod. No secret in it: it names
# the token file to read and the SA to impersonate.
output "credential_config" {
  value = jsonencode({
    type                              = "external_account"
    audience                          = "//iam.googleapis.com/${google_iam_workload_identity_pool_provider.k8s.name}"
    subject_token_type                = "urn:ietf:params:oauth:token-type:jwt"
    token_url                         = "https://sts.googleapis.com/v1/token"
    service_account_impersonation_url = "https://iamcredentials.googleapis.com/v1/projects/-/serviceAccounts/${google_service_account.stt.email}:generateAccessToken"
    credential_source                 = { file = "/var/run/secrets/gcp-wif/token" }
  })
}

# Hostname of Vertex AI's eu multi-region endpoint, for the regional PSC
# endpoint in the VPN module. Waits for the API: PSC doesn't enable it.
output "aiplatform_eu_rep_host" {
  value      = "aiplatform.eu.rep.googleapis.com"
  depends_on = [google_project_service.aiplatform]
}
