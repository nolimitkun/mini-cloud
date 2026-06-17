# Hybrid Multi-Cloud Architecture — Documentation

A **hybrid, multi-cloud** design where an **on-prem private cloud is the hub** and **AWS, Azure, and
GCP are spokes**, connected over **private circuits only**, with **no public exposure** of any cloud
service and **no Internet path** for inter-site traffic.

## Design at a glance

- **Two-tier hub-and-spoke.** Tier 1: on-prem hub ↔ each cloud (spoke). Tier 2: inside each cloud, a
  landing-zone **cloud hub** ↔ its **workload spokes**.
- **Dedicated private circuits** per provider — Direct Connect (AWS), ExpressRoute (Azure), Cloud
  Interconnect (GCP). No public Internet on the data plane.
- **Private endpoints only** — PrivateLink / Private Endpoint / PSC. No public IPs, IGWs, or public
  PaaS endpoints anywhere (enforced by guardrails).
- **Hybrid inspection** — cloud-native firewall per cloud hub for east-west; on-prem NGFW for
  anything touching on-prem. Cross-cloud traffic hairpins through on-prem (no spoke-to-spoke).
- **Central control** — one routing domain (ASN 65000), one authoritative private DNS namespace,
  one IdP, org-level guardrails so new spokes are non-public by default.

## Locked decisions

| # | Decision | Choice |
|---|----------|--------|
| D1 | Circuit topology | Dedicated circuits per provider |
| D2 | Inspection placement | Hybrid (cloud firewalls + on-prem NGFW) |
| D3 | Region scope | Single region per cloud |
| D4 | In-cloud hubs | AWS TGW · Azure hub VNet · GCP Shared VPC/NCC |

## Documents

| # | Doc | Covers |
|---|-----|--------|
| 01 | [Architecture specification](01-architecture-specification.md) | Goals, requirements, topology, 2-tier hub-and-spoke, decisions |
| 02 | [Network design](02-network-design.md) | IPAM/CIDR, BGP/ASN, route tables, east-west, resilience |
| 03 | [Connectivity buildout](03-connectivity-buildout.md) | Circuit ordering, colo, per-provider gateway build, acceptance |
| 04 | [Security baseline](04-security-baseline.md) | SCP / Azure Policy / Org Policy guardrails as code |
| 05 | [DNS design](05-dns-design.md) | Namespace, resolvers, forwarding, split-horizon |
| 06 | [Buildout runbook](06-buildout-runbook.md) | Phased, checkbox execution plan with gates |
| 07 | [Cost estimate](07-cost-estimate.md) | Illustrative list-price monthly/annual platform cost |
| 08 | [PoC — VPN (GCP)](08-poc-vpn.md) | LAN-as-on-prem + strongSwan site-to-site VPN to GCP (overrides D1 for PoC) |

## Infrastructure as code

The [`../infra`](../infra/README.md) directory holds the Terraform skeleton: per-cloud landing-zone
modules (`hub` + `spoke` for AWS, Azure, GCP), composition stacks (`stacks/aws|azure|gcp`), and the
guardrail policies from doc 04. AWS, Azure, and GCP hub+spoke modules are all built out; circuit
ids, project/subscription ids, and state backends remain as `# TODO` placeholders.

## Open items

1. Controlled Internet egress — fully air-gapped vs. a single audited on-prem egress path.
2. Circuit redundancy depth — dual POPs per provider from day one vs. phased.
