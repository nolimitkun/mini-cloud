variable "project_id" {
  type = string
}

variable "service_account_id" {
  type    = string
  default = "litellm-stt"
}

variable "pool_id" {
  type    = string
  default = "onprem-k8s"
}

variable "provider_id" {
  type    = string
  default = "minikube"
}

variable "k8s_issuer" {
  type        = string
  default     = "https://kubernetes.default.svc.cluster.local"
  description = "The cluster's service-account issuer (kubectl get --raw /.well-known/openid-configuration)."
}

variable "k8s_jwks" {
  type        = string
  description = "The cluster's public signing keys (kubectl get --raw /openid/v1/jwks). Public data; changes when the cluster is recreated."
}

variable "k8s_subjects" {
  type = list(string)
  # LiteLLM and agentgateway's proxy, side by side while clients move to
  # agentgateway (docs/gcp/ai-inference.md); LiteLLM's entry goes after.
  default = [
    "system:serviceaccount:mini-platform:litellm",
    "system:serviceaccount:agentgateway-system:agentgateway-proxy",
  ]
  description = "The only Kubernetes service accounts allowed to impersonate the SA."
  validation {
    condition     = length(var.k8s_subjects) > 0 && alltrue([for s in var.k8s_subjects : can(regex("^system:serviceaccount:[a-z0-9-]+:[a-z0-9-]+$", s))])
    error_message = "Each k8s_subjects entry must be system:serviceaccount:<namespace>:<name>."
  }
}

variable "manage_location_policy" {
  type        = bool
  default     = true
  description = "Manage the project's gcp.resourceLocations exception (adds eu) here. false when an org admin creates and owns it outside this state."
}
