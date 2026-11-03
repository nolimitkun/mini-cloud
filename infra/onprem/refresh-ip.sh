#!/usr/bin/env bash
# Re-point the GCP VPN PoC after the on-prem public IP changes (e.g. a dynamic
# ISP IP like an Orange Livebox). Updates BOTH sides: the GCP external VPN
# gateway (via terraform) and the strongSwan local id, then restarts the tunnel.
#
# The IP change replaces the external gateway + tunnel; the plan is shown and
# confirmed before anything is applied (--yes skips the prompt). Also syncs the
# GCP_POC_TFVARS repo secret so the CI plan job sees the same IP.
#
# Run as your NORMAL user (it calls sudo only for the strongSwan steps):
#   bash infra/onprem/refresh-ip.sh [--yes]
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
STACK="$SCRIPT_DIR/../stacks/gcp-poc"
TFVARS="$STACK/terraform.tfvars"
TF=$(command -v terraform || echo "$HOME/.local/bin/terraform")
YES=false; [ "${1:-}" = "--yes" ] && YES=true

NEWIP=$(curl -fsS --max-time 8 https://api.ipify.org 2>/dev/null || curl -fsS --max-time 8 https://ifconfig.me 2>/dev/null || true)
[ -n "$NEWIP" ] || { echo "could not detect public IP"; exit 1; }
CURIP=$(grep onprem_public_ip "$TFVARS" | sed 's/.*= *"//; s/".*//')
echo "public IP: configured=$CURIP  current=$NEWIP"
[ "$NEWIP" = "$CURIP" ] && { echo "unchanged — nothing to do."; exit 0; }

echo "== 1/3 update GCP external gateway (terraform) =="
PLAN=$(mktemp)
APPLIED=false
cp "$TFVARS" "$TFVARS.bak"
# Any exit before the apply (plan error, declined prompt) restores the tfvars.
trap 'rm -f "$PLAN"; if ! $APPLIED && [ -f "$TFVARS.bak" ]; then mv "$TFVARS.bak" "$TFVARS"; echo "tfvars restored."; fi' EXIT
sed -i "s|^onprem_public_ip *=.*|onprem_public_ip = \"$NEWIP\"|" "$TFVARS"
"$TF" -chdir="$STACK" plan -input=false -out="$PLAN" > /dev/null
echo "planned changes (expect the external gateway + tunnel to be replaced):"
"$TF" -chdir="$STACK" show -json "$PLAN" | python3 -c '
import json, sys
changes = [r for r in json.load(sys.stdin).get("resource_changes", [])
           if r["change"]["actions"] not in (["no-op"], ["read"])]
for r in changes:
    a = r["change"]["actions"]
    print("  " + ("replace" if sorted(a) == ["create", "delete"] else ",".join(a)) + "  " + r["address"])
print("  (none: GCP already has this IP)" if not changes else "")'
if ! $YES; then
  read -r -p "apply this plan? [y/N] " ok
  if [ "$ok" != y ] && [ "$ok" != Y ]; then
    echo "aborted — nothing applied."
    exit 1
  fi
fi
"$TF" -chdir="$STACK" apply -input=false "$PLAN"
APPLIED=true
rm -f "$TFVARS.bak"

echo "== 2/3 sync CI secret GCP_POC_TFVARS =="
if command -v gh > /dev/null && (cd "$SCRIPT_DIR" && gh secret set GCP_POC_TFVARS < "$TFVARS"); then
  echo "secret updated."
else
  echo "WARNING: could not update the GCP_POC_TFVARS secret; the CI plan will show the gateway" \
       "being replaced back until you run: gh secret set GCP_POC_TFVARS < $TFVARS"
fi

echo "== 3/3 update on-prem strongSwan local id + restart tunnel =="
if [ -f /etc/swanctl/swanctl.conf ]; then
  # the old IP appears only as the local id; replace that value
  sudo sed -i "s|${CURIP//./\\.}|$NEWIP|g" /etc/swanctl/swanctl.conf
  sudo swanctl --load-all
  sudo swanctl --terminate --ike gcp 2>/dev/null || true
  sudo swanctl --initiate --child gcp || true
  # ipsec0 carries BGP; it is gone after a reboot unless mini-cloud-vpn.service is installed.
  if ! ip link show ipsec0 > /dev/null 2>&1; then
    echo "ipsec0 missing — recreating it and restarting FRR"
    sudo "$SCRIPT_DIR/strongswan/ipsec-xfrm.sh"
    sudo systemctl restart frr
  fi
  echo "done. check: sudo swanctl --list-sas"
else
  echo "strongSwan not configured yet — bring up the on-prem side first."
fi
