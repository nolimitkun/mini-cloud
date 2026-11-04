#!/usr/bin/env bash
# Re-upload the on-prem cluster's public signing keys to the GCP workload
# identity provider (onprem-k8s/minikube). Needed after the cluster is
# recreated (e.g. `minikube delete` / deploy-minikube.sh --reset): new keys
# sign the LiteLLM pod's token, and GCP rejects it until it knows them.
#
# Writes infra/stacks/gcp-poc/onprem-k8s-jwks.json, then plans and (after a
# confirmation; --yes skips it) applies the stack. Commit the JSON afterwards so
# the CI plan sees the same keys. Run as your normal user, with kubectl
# pointing at the cluster.
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
STACK="$SCRIPT_DIR/../stacks/gcp-poc"
JWKS="$STACK/onprem-k8s-jwks.json"
TF=$(command -v terraform || echo "$HOME/.local/bin/terraform")
YES=false; [ "${1:-}" = "--yes" ] && YES=true

NEW=$(kubectl get --raw /openid/v1/jwks | python3 -m json.tool)
# The file only ever holds keys that were applied: any exit before a successful
# apply (plan error, declined prompt, failed apply) restores the previous copy,
# so a re-run sees the change again instead of reporting "unchanged".
if [ "$NEW" = "$(cat "$JWKS" 2>/dev/null)" ]; then
  echo "cluster keys unchanged — nothing to do."
  exit 0
fi
PLAN=$(mktemp)
APPLIED=false
cp "$JWKS" "$JWKS.bak"
trap 'rm -f "$PLAN"; if ! $APPLIED && [ -f "$JWKS.bak" ]; then mv "$JWKS.bak" "$JWKS"; echo "keys file restored."; fi' EXIT
printf '%s\n' "$NEW" > "$JWKS"
echo "cluster keys changed; wrote $JWKS"

"$TF" -chdir="$STACK" plan -input=false -out="$PLAN" > /dev/null
"$TF" -chdir="$STACK" show -no-color "$PLAN" | grep -E '^  # ' || echo "  (no changes)"
if ! $YES; then
  read -r -p "apply this plan? [y/N] " ok
  if [ "$ok" != y ] && [ "$ok" != Y ]; then
    echo "aborted — nothing applied."
    exit 1
  fi
fi
"$TF" -chdir="$STACK" apply -input=false "$PLAN"
APPLIED=true
rm -f "$JWKS.bak"
echo "done. commit $JWKS so CI plans with the same keys."
