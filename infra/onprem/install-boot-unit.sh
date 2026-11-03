#!/usr/bin/env bash
# Install + enable the boot unit that restores the GCP PoC tunnel after a reboot
# (systemd/mini-cloud-vpn.service). Run as root: sudo infra/onprem/install-boot-unit.sh
#
# Enables it for the next boot only; it does not touch a tunnel that is up now.
# To apply immediately (recreates ipsec0 — BGP flaps for a few seconds):
#   sudo systemctl restart mini-cloud-vpn
set -euo pipefail

DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
[ "$(id -u)" = 0 ] || { echo "run as root (sudo $0)" >&2; exit 1; }

install -m 0755 "$DIR/strongswan/ipsec-xfrm.sh" /usr/local/sbin/mini-cloud-ipsec-xfrm.sh
install -m 0644 "$DIR/systemd/mini-cloud-vpn.service" /etc/systemd/system/mini-cloud-vpn.service
systemctl daemon-reload
systemctl enable mini-cloud-vpn.service
systemctl enable strongswan-starter.service frr.service

echo "enabled: mini-cloud-vpn.service (runs at next boot)"
