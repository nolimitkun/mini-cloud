#!/usr/bin/env bash
# Re-point the GCP VPN PoC after the on-prem public IP changes (e.g. a dynamic
# ISP IP like an Orange Livebox). Updates BOTH sides: the GCP external VPN
# gateway (via terraform) and the strongSwan local id, then restarts the tunnel.
#
# Run as your NORMAL user (it calls sudo only for the strongSwan steps):
#   bash infra/onprem/refresh-ip.sh
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
STACK="$SCRIPT_DIR/../stacks/gcp-poc"
TF=$(command -v terraform || echo "$HOME/.local/bin/terraform")

NEWIP=$(curl -fsS --max-time 8 https://api.ipify.org 2>/dev/null || curl -fsS --max-time 8 https://ifconfig.me 2>/dev/null || true)
[ -n "$NEWIP" ] || { echo "could not detect public IP"; exit 1; }
CURIP=$(grep onprem_public_ip "$STACK/terraform.tfvars" | sed 's/.*= *"//; s/".*//')
echo "public IP: configured=$CURIP  current=$NEWIP"
[ "$NEWIP" = "$CURIP" ] && { echo "unchanged — nothing to do."; exit 0; }

echo "== 1/2 update GCP external gateway (terraform) =="
sed -i "s|^onprem_public_ip *=.*|onprem_public_ip = \"$NEWIP\"|" "$STACK/terraform.tfvars"
"$TF" -chdir="$STACK" apply -auto-approve

echo "== 2/2 update on-prem strongSwan local id + restart tunnel =="
if [ -f /etc/swanctl/swanctl.conf ]; then
  sudo sed -i "s|\(local *{ auth = psk; id = \)[0-9.]\+|\1$NEWIP|" /etc/swanctl/swanctl.conf
  sudo swanctl --load-all
  sudo swanctl --terminate --ike gcp 2>/dev/null || true
  sudo swanctl --initiate --child gcp || true
  echo "done. check: sudo swanctl --list-sas"
else
  echo "strongSwan not configured yet — bring up the on-prem side first."
fi
