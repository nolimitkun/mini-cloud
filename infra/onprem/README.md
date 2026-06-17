# On-prem VPN endpoint (PoC)

Config for the **on-prem side** of the GCP VPN PoC ([docs/08-poc-vpn.md](../../docs/08-poc-vpn.md)):
a Linux host on the LAN running **strongSwan** (IPsec) + **FRR** (BGP).

```
onprem/
├── strongswan/
│   ├── swanctl.conf     # IPsec/IKEv2 PSK, route-based (XFRM if_id 42)
│   └── ipsec-xfrm.sh    # creates ipsec0 + BGP link-local IP
└── frr/
    └── bgpd.conf        # eBGP 65000 <-> 65020 over the tunnel
```

## Apply order

```bash
# 0. Deploy the cloud side first (infra/stacks/gcp-poc), grab `terraform output`.
sudo apt-get install -y strongswan strongswan-swanctl frr   # Debian/Ubuntu

# 1. IPsec
sudo cp strongswan/swanctl.conf /etc/swanctl/swanctl.conf   # edit <PLACEHOLDERS> first
sudo swanctl --load-all

# 2. Routed interface + BGP link-local IP (set WAN_IF to your uplink NIC)
sudo WAN_IF=eth0 strongswan/ipsec-xfrm.sh

# 3. BGP
sudo cp frr/bgpd.conf /etc/frr/bgpd.conf                    # edit LAN network first
sudo sed -i 's/^bgpd=no/bgpd=yes/' /etc/frr/daemons
sudo systemctl restart frr
```

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
