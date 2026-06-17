# PoC — LAN-as-on-prem over Site-to-Site VPN (GCP first)

**Status:** PoC v0.1
**Purpose:** Prove the hub-and-spoke pattern end-to-end **cheaply**, using the **local LAN as the
on-prem hub** and an **IPsec VPN over the public Internet** instead of a dedicated circuit.

> This **overrides decision D1** *for the PoC only*. Dedicated Direct Connect / ExpressRoute /
> Cloud Interconnect ([01 §7](01-architecture-specification.md)) are replaced by managed cloud VPN
> gateways + on-prem strongSwan. Everything else — hub-and-spoke, BGP (ASN 65000↔65020), private
> workloads, no public service exposure — is preserved so the PoC validates the real design.

---

## 1. What "no public exposure" means here

The IPsec tunnel runs over the Internet, so **two public IPs are unavoidable**: the GCP HA VPN
gateway and the on-prem WAN IP. These are **tunnel endpoints only**. The actual workloads (the test
VM, any PaaS) keep **no external IP** — they are reachable solely through the encrypted tunnel. That
preserves G2 (no public exposition of *services*); the VPN gateway is the controlled door, like the
circuit termination is in production.

---

## 2. Topology

```
   LAN 192.168.1.0/24                          GCP VPC 10.48.0.0/24 (hub)
 ┌─────────────────────┐    IPsec/IKEv2     ┌────────────────────────────┐
 │  LAN hosts          │    + BGP over      │  Cloud Router (ASN 65020)  │
 │      │              │    169.254.0.0/30  │        │                   │
 │  strongSwan host  ◀─┼════════════════════┼▶  HA VPN gateway           │
 │  (FRR/bgpd)         │   UDP 500/4500     │        │                   │
 │  ASN 65000          │                    │   test VM (no ext IP)      │
 └─────────────────────┘                    └────────────────────────────┘
```

- **On-prem hub** = the LAN; a Linux box runs **strongSwan** (IPsec) + **FRR** (BGP).
- **GCP spoke** = a VPC with one `10.48.0.0/24` subnet, **HA VPN gateway**, **Cloud Router**, and a
  test VM with no external IP.
- **Routing:** BGP over the tunnel (link-local `169.254.0.0/30`). On-prem advertises the LAN; GCP
  advertises `10.48.0.0/24`.

---

## 3. Addressing & identifiers

| Item | Value (PoC default) | Notes |
|------|--------------------|-------|
| LAN CIDR | `192.168.1.0/24` | Set to your real LAN range |
| GCP VPC subnet | `10.48.0.0/24` | From the GCP supernet ([02 §1](02-network-design.md)) |
| On-prem ASN | `65000` | Matches prod design |
| GCP Cloud Router ASN | `65020` | Matches prod design |
| BGP link-local (GCP / on-prem) | `169.254.0.1` / `169.254.0.2` | `/30` inside the tunnel |
| IKE | IKEv2, PSK | aes256 · sha256 · DH group 14 (modp2048) |
| ESP | aes256 · sha256 · PFS group 14 | GCP-supported cipher set |

---

## 4. Prerequisites

- A GCP project with billing + the Compute API enabled, and `gcloud` / Terraform creds.
- A Linux host on the LAN with a **reachable public IP**. Behind home NAT: forward **UDP 500 and
  4500** to the strongSwan host and use its public (NAT) IP as the peer IP; NAT-T handles the rest.
- Packages on the strongSwan host: `strongswan-swanctl` (or `strongswan`), `frr`.
- IP forwarding enabled: `net.ipv4.ip_forward=1`.

---

## 5. Build steps

### 5.1 Cloud side (Terraform)

```bash
cd infra/stacks/gcp-poc
cp terraform.tfvars.example terraform.tfvars   # fill project_id, onprem_public_ip, lan_cidr, shared_secret
terraform init
terraform apply
terraform output                                # note: vpn_gateway_ip, bgp_gcp_ip, test_vm_internal_ip
```

This creates the VPC + subnet, HA VPN gateway, external peer gateway (your on-prem IP), Cloud Router
with the BGP peer, the tunnel, firewall rules (LAN CIDR + IAP), and a no-external-IP test VM.

### 5.2 On-prem side (strongSwan + FRR)

Configs live in [`infra/onprem/`](../infra/onprem/README.md). Substitute the Terraform outputs:

```bash
# 1. IPsec — edit infra/onprem/strongswan/swanctl.conf:
#    remote_addrs / remote id  -> vpn_gateway_ip (output)
#    local id                  -> your on-prem public IP
#    secret                    -> the shared_secret you set
sudo cp infra/onprem/strongswan/swanctl.conf /etc/swanctl/swanctl.conf
sudo swanctl --load-all

# 2. Routed IPsec interface (XFRM if_id 42) + BGP link-local IP
sudo infra/onprem/strongswan/ipsec-xfrm.sh         # creates ipsec0, adds 169.254.0.2/30

# 3. BGP — edit neighbor/network in infra/onprem/frr/bgpd.conf, then:
sudo cp infra/onprem/frr/bgpd.conf /etc/frr/bgpd.conf
sudo sed -i 's/^bgpd=no/bgpd=yes/' /etc/frr/daemons
sudo systemctl restart frr
```

---

## 6. Verification

| Check | Command | Expect |
|-------|---------|--------|
| IPsec up | `sudo swanctl --list-sas` | `ESTABLISHED`, child `INSTALLED` |
| GCP tunnel | `gcloud compute vpn-tunnels describe <name> --region europe-west1` | `detailedStatus: Tunnel is up and running` |
| BGP (on-prem) | `sudo vtysh -c 'show ip bgp summary'` | neighbor `169.254.0.1` state `Established` |
| BGP (GCP) | `gcloud compute routers get-status <router> --region europe-west1` | learned route `192.168.1.0/24` |
| Route present | `ip route get 10.48.0.10` | via `ipsec0` |
| Data plane | `ping <test_vm_internal_ip>` from LAN | replies over the tunnel |
| No public exposure | test VM has no external IP; `gcloud compute instances list` | `EXTERNAL_IP` empty |

SSH the test VM without a public IP via IAP: `gcloud compute ssh <vm> --tunnel-through-iap`.

---

## 7. From PoC to production

| PoC | Production target |
|-----|-------------------|
| IPsec VPN over Internet | Dedicated circuit (D1) — swap the transport, keep BGP |
| Single tunnel (no SLA) | HA VPN dual tunnels / dual circuits ([06](06-buildout-runbook.md)) |
| LAN box (strongSwan+FRR) | Colo edge routers ([03 §2](03-connectivity-buildout.md)) |
| One cloud (GCP) | Replicate pattern to AWS (Site-to-Site VPN→TGW) and Azure (VPN Gateway→hub VNet) |
| Org guardrails optional | Apply `policy/` before workloads ([04](04-security-baseline.md)) |

The BGP design, CIDR plan, and hub-and-spoke routing carry over unchanged — only the **transport**
(VPN → circuit) and **redundancy** (single → dual) change.

---

## 8. Cost

List price, EU region (europe-west1), ~730 hrs/month. The on-prem side is **$0 incremental** — it
reuses the existing LAN host and internet connection.

| Item | Rate | Monthly |
|------|------|---------|
| HA VPN tunnel (1, PoC) | $0.05/hr | ~$37 |
| Cloud Router + HA VPN gateway + external gateway | free | $0 |
| Test VM (e2-micro, europe-west1) | ~$0.009/hr | ~$7 |
| Boot disk (10 GB pd-balanced) | ~$0.10/GB | ~$1 |
| Egress over VPN (internet egress) | ~$0.12/GB | ~$1 at a few GB of testing |
| **PoC total (running)** | | **≈ $45–50/mo** |

Notes:

- **vs. the production circuit design** (~$3,520/mo GCP fixed, [07 §2.3](07-cost-estimate.md)), the
  VPN PoC is **~1–2%** of the cost — the whole point of using VPN for the PoC.
- **Tear it down between sessions** ([§9 teardown](#9-teardown)) → recurring cost drops to ~$0.
- **No free-tier VM in Europe:** GCP's always-free `e2-micro` exists only in `us-central1` /
  `us-west1` / `us-east1`, so the ~$7 VM line stands for a Europe footprint. Stop/destroy the VM
  when idle instead, or run the test workload directly on the on-prem host.
- **Egress scales with traffic**: VPN traffic to on-prem is billed as internet egress (~$0.085–0.12/GB);
  keep test transfers small. Ingress to GCP is free.

---

## 9. Teardown

```bash
cd infra/stacks/gcp-poc && terraform destroy
sudo swanctl --terminate --ike gcp ; sudo ip link del ipsec0
```

VPN data transfer (egress) is billed per GB; tearing down the PoC stops all recurring charge except
trivial idle. See [07 §4](07-cost-estimate.md) — a VPN PoC is a tiny fraction of the circuit-based estimate.
