#!/usr/bin/env bash
# Create the routed IPsec (XFRM) interface for the GCP PoC tunnel and assign the
# BGP link-local IP. if_id (42) must match if_id_in/if_id_out in swanctl.conf.
# Run as root after `swanctl --load-all`. Idempotent-ish: deletes any existing ipsec0.
set -euo pipefail

IFID=42
IFNAME=ipsec0
ONPREM_BGP_IP=169.254.0.2/30          # must match module var bgp_onprem_ip
# Uplink NIC: the default route's (lowest-metric) device unless overridden,
# e.g. WAN_IF=enp1s0 ./ipsec-xfrm.sh
WAN_IF="${WAN_IF:-$(ip -4 route show default | awk '{for (i = 1; i < NF; i++) if ($i == "dev") { print $(i + 1); exit }}')}"
[ -n "$WAN_IF" ] || { echo "no default route; set WAN_IF" >&2; exit 1; }

ip link del "$IFNAME" 2>/dev/null || true
ip link add "$IFNAME" type xfrm dev "$WAN_IF" if_id "$IFID"
ip link set "$IFNAME" up
ip addr add "$ONPREM_BGP_IP" dev "$IFNAME"

# Forwarding + relaxed reverse-path filtering for the tunnel interface.
sysctl -w net.ipv4.ip_forward=1
sysctl -w "net.ipv4.conf.${IFNAME}.rp_filter=0"
sysctl -w "net.ipv4.conf.${WAN_IF}.rp_filter=0"

echo "Created $IFNAME (if_id $IFID) with $ONPREM_BGP_IP on $WAN_IF."
echo "Next: load FRR bgpd.conf and bring up BGP to the Cloud Router."
