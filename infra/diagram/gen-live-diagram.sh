#!/usr/bin/env bash
# Generate a LIVE infrastructure diagram from Terraform state via Inframap.
# Cloud resources come from the state (so it follows every apply); the on-prem
# side (which no cloud tool can see) is injected as a fixed node linked to the
# external VPN gateway.
#
# Usage: gen-live-diagram.sh <tfstate-path> <output-svg>
# Requires: inframap (~/.local/bin), graphviz (dot).
set -euo pipefail

STATE="${1:?usage: gen-live-diagram.sh <tfstate> <out.svg>}"
OUT="${2:?usage: gen-live-diagram.sh <tfstate> <out.svg>}"
INFRAMAP="${INFRAMAP:-$(command -v inframap || echo "$HOME/.local/bin/inframap")}"
TMP="$(mktemp)"

# Cloud graph from live state (--raw keeps every resource; GCP isn't covered by
# Inframap's connection pruning).
"$INFRAMAP" generate --tfstate --raw "$STATE" > "$TMP"

# Inject the on-prem node + the IPsec/BGP edge to the external VPN gateway,
# then re-close the graph. Skip cleanly if the gateway node isn't present.
PEER='module.vpn_poc.google_compute_external_vpn_gateway.peer'
if grep -q "$PEER" "$TMP"; then
  head -n -1 "$TMP" > "${TMP}.g"
  cat >> "${TMP}.g" <<EOF
  "onprem" [label="On-prem LAN\n192.168.1.0/24\nstrongSwan + FRR (AS 65000)", shape=box, style="filled,rounded", fillcolor="#FAECE7"];
  "onprem" -> "$PEER" [label="IPsec + BGP", color="#993C1D", penwidth=2];
}
EOF
  mv "${TMP}.g" "$TMP"
fi

dot -Tsvg "$TMP" -o "$OUT"
rm -f "$TMP"
echo "wrote $OUT"
