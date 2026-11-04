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

# Source address for traffic this host sends into the tunnel. Routes learned
# over BGP point at ipsec0, so the kernel would pick its link-local address
# (169.254.0.2) as the source; GCP has no route back to it. Rewrite the source
# to this host's LAN address, which BGP advertises. BGP itself (to
# 169.254.0.1) keeps the link-local address. Rebuilt on every run, so a new
# DHCP lease is picked up by the next boot or re-run.
LAN_IP="${LAN_IP:-$(ip -4 -o addr show dev "$WAN_IF" scope global | awk '{ split($4, a, "/"); print a[1]; exit }')}"
[ -n "$LAN_IP" ] || { echo "no IPv4 address on $WAN_IF; set LAN_IP" >&2; exit 1; }
command -v nft > /dev/null || { echo "nft not found; install nftables" >&2; exit 1; }
nft delete table ip mini_cloud_vpn 2>/dev/null || true
nft -f - <<NFT
table ip mini_cloud_vpn {
  chain postrouting {
    type nat hook postrouting priority srcnat;
    oifname "$IFNAME" ip saddr 169.254.0.0/16 ip daddr != ${ONPREM_BGP_IP%.*}.0/30 snat to $LAN_IP
  }
}
NFT

echo "Created $IFNAME (if_id $IFID) with $ONPREM_BGP_IP on $WAN_IF; tunnel traffic leaves as $LAN_IP."
echo "Next: load FRR bgpd.conf and bring up BGP to the Cloud Router."
