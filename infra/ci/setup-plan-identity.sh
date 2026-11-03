#!/usr/bin/env bash
# One-time setup for the PR `terraform plan` job (.github/workflows/terraform-plan.yml):
# a GitHub OIDC Workload Identity Federation pool + a read-only service account.
# No key files — GitHub exchanges its OIDC token for short-lived SA credentials.
#
# Idempotent: re-running skips what already exists. Needs owner (or IAM admin +
# WIF admin) on both projects.
set -euo pipefail

HUB=mini-cloud-499820
SPOKE=mini-cloud-lakehouse
REPO=nolimitkun/mini-cloud
STATE_BUCKET=mini-cloud-499820-tfstate
POOL=github
PROVIDER=github-oidc
SA_ID=tf-plan-ci
SA="${SA_ID}@${HUB}.iam.gserviceaccount.com"

HUB_NUMBER=$(gcloud projects describe "$HUB" --format='value(projectNumber)')

gcloud services enable iamcredentials.googleapis.com sts.googleapis.com --project "$HUB"

gcloud iam workload-identity-pools describe "$POOL" --location=global --project "$HUB" >/dev/null 2>&1 ||
  gcloud iam workload-identity-pools create "$POOL" --location=global --project "$HUB" \
    --display-name="GitHub Actions"

# Only tokens minted for this repository are accepted.
gcloud iam workload-identity-pools providers describe "$PROVIDER" --location=global \
  --workload-identity-pool="$POOL" --project "$HUB" >/dev/null 2>&1 ||
  gcloud iam workload-identity-pools providers create-oidc "$PROVIDER" --location=global \
    --workload-identity-pool="$POOL" --project "$HUB" \
    --display-name="GitHub OIDC" \
    --issuer-uri="https://token.actions.githubusercontent.com" \
    --attribute-mapping="google.subject=assertion.sub,attribute.repository=assertion.repository,attribute.event_name=assertion.event_name" \
    --attribute-condition="assertion.repository=='${REPO}'"

gcloud iam service-accounts describe "$SA" --project "$HUB" >/dev/null 2>&1 ||
  gcloud iam service-accounts create "$SA_ID" --project "$HUB" \
    --display-name="terraform plan (PR CI, read-only)"

# Read-only: resource reads (viewer), IAM policy reads (securityReviewer), and
# quota-project use for the BigLake calls made with user_project_override.
for project in "$HUB" "$SPOKE"; do
  for role in roles/viewer roles/iam.securityReviewer roles/serviceusage.serviceUsageConsumer; do
    gcloud projects add-iam-policy-binding "$project" --member="serviceAccount:${SA}" \
      --role="$role" --condition=None --quiet >/dev/null
  done
done

# State is read with -lock=false, so object read access is enough.
gcloud storage buckets add-iam-policy-binding "gs://${STATE_BUCKET}" \
  --member="serviceAccount:${SA}" --role=roles/storage.objectViewer >/dev/null

gcloud iam service-accounts add-iam-policy-binding "$SA" --project "$HUB" \
  --role=roles/iam.workloadIdentityUser \
  --member="principalSet://iam.googleapis.com/projects/${HUB_NUMBER}/locations/global/workloadIdentityPools/${POOL}/attribute.repository/${REPO}" >/dev/null

echo "workload_identity_provider: projects/${HUB_NUMBER}/locations/global/workloadIdentityPools/${POOL}/providers/${PROVIDER}"
echo "service_account:            ${SA}"
