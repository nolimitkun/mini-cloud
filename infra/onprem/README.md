# On-prem VPN endpoint (PoC)

Config for the **on-prem side** of the GCP VPN PoC ([docs/08-poc-vpn.md](../../docs/08-poc-vpn.md)):
a Linux host on the LAN running **strongSwan** (IPsec) + **FRR** (BGP).

```
onprem/
├── strongswan/
│   ├── swanctl.conf     # IPsec/IKEv2 PSK, route-based (XFRM if_id 42)
│   └── ipsec-xfrm.sh    # creates ipsec0 + BGP link-local IP
├── frr/
│   └── bgpd.conf        # eBGP 65000 <-> 65020 over the tunnel
├── systemd/
│   └── mini-cloud-vpn.service  # restores the tunnel after a reboot
├── install-boot-unit.sh # installs + enables that unit
└── refresh-ip.sh        # re-points both sides after a public IP change
```

## Apply order

```bash
# 0. Deploy the cloud side first (infra/stacks/gcp-poc), grab `terraform output`.
sudo apt-get install -y strongswan strongswan-swanctl frr   # Debian/Ubuntu

# 1. IPsec
sudo cp strongswan/swanctl.conf /etc/swanctl/swanctl.conf   # edit <PLACEHOLDERS> first
sudo swanctl --load-all

# 2. Routed interface + BGP link-local IP (uplink NIC = default route's; override with WAN_IF=...)
sudo strongswan/ipsec-xfrm.sh

# 3. BGP
sudo cp frr/bgpd.conf /etc/frr/bgpd.conf                    # edit LAN network first
sudo sed -i 's/^bgpd=no/bgpd=yes/' /etc/frr/daemons
sudo systemctl restart frr

# 4. Survive reboots (see below)
sudo ./install-boot-unit.sh
```

## After a reboot or IP change

Two things break the tunnel without any config change:

- **Reboot.** `strongswan-starter` only starts charon from `ipsec.conf`, so nothing reloads
  `/etc/swanctl/swanctl.conf`, and `ipsec0` isn't persistent. `mini-cloud-vpn.service` (installed by
  `install-boot-unit.sh`) runs `swanctl --load-all` and recreates `ipsec0` before FRR starts.
  It only takes effect from the next boot; `sudo systemctl restart mini-cloud-vpn` applies it now
  (BGP flaps for a few seconds).
- **New public IP** (dynamic ISP addresses). GCP's tunnel shows `NO_INCOMING_PACKETS`. Run
  `bash refresh-ip.sh` as your normal user: it shows the plan (the external gateway and tunnel are
  replaced) and asks before applying, syncs the `GCP_POC_TFVARS` secret for the CI plan job,
  updates the strongSwan local id, and recreates `ipsec0` if it's missing.

## Verify

```bash
sudo swanctl --list-sas                 # ESTABLISHED / INSTALLED
sudo vtysh -c 'show ip bgp summary'     # neighbor 169.254.0.1 Established
ip route get 10.48.0.10                 # via ipsec0
ping <test_vm_internal_ip>              # data plane over the tunnel
```

## Notes

- **Behind NAT:** forward UDP 500 + 4500 to this host; use the public/NAT IP as `local id` and as
  `onprem_public_ip` in the cloud tfvars. NAT-T is automatic.
- **Reach from other LAN hosts:** either add a route for `10.48.0.0/24` via this host on the LAN
  gateway, or test directly from this host.
- These files contain `<PLACEHOLDERS>` and a sample PSK — never commit a real pre-shared key.
