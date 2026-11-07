# GCP — Production Landing Zone

The production target for GCP as one of the three cloud spokes of the on-prem hub: a Shared VPC /
NCC landing zone in `europe-west1`, reached over Cloud Interconnect, with Google APIs consumed
through Private Service Connect only. What runs today is the smaller PoC version of it, described in
[the GCP hub-and-spoke](README.md).

**Status:** Terraform written and validated offline, with `TODO` placeholders for circuit ids and
the state backend. Not deployed.

← [Project overview](../../README.md) · [Shared design](../README.md) · [AWS](../aws/README.md) · [Azure](../azure/README.md) · [GCP](README.md)

---

## Landing zone

| Layer | GCP construct |
|-------|---------------|
| Org / tenancy | Organization + folders + projects |
| Cloud hub (Tier-2 hub) | Host project: **Shared VPC** + Network Connectivity Center + Interconnect attachments |
| Inspection | Firewall policy / NVA in the host VPC |
| Shared services | Host project: Cloud DNS, PSC endpoints |
| Workload spokes | Service projects attached to the Shared VPC |
| Guardrails | Org Policy at folder level |

## Addressing and routing

| Item | Value |
|------|-------|
| Region | `europe-west1` |
| Private supernet | `10.48.0.0/12` (hub `10.48.0.0/20`, prod `10.48.16.0/20`, non-prod `10.48.32.0/20`, shared `10.48.48.0/20`, endpoints `10.48.64.0/20`) |
| Cross-cloud block | `172.19.0.0/16` |
| BGP | Cloud Router ASN `65020` ↔ on-prem `65000` over two VLAN attachments |
| DNS | Cloud DNS inbound forwarding entry point + outbound forwarding zones; private zones for `gcp.corp.internal` |

The full plan is in [doc 02](../architecture/02-network-design.md) and [doc 05](../architecture/05-dns-design.md).

---

## Connectivity build

Production build steps for the private circuit and the cloud hub (the shared sequence and colo edge
are in [doc 03](../architecture/03-connectivity-buildout.md)).

| Step | Action |
|------|--------|
| 1 | Order **Dedicated Interconnect** at the colocation facility; provision 2× VLAN attachments. |
| 2 | Create **Cloud Router** (ASN `65020`) per attachment for HA (two interfaces). |
| 3 | eBGP `65000 ↔ 65020`; advertise `10.48.0.0/12`; enable BFD. |
| 4 | Host project **Shared VPC** = cloud hub; attach service projects (spokes). Add **NCC** hub if multi-VPC. |
| 5 | Firewall policy / NVA in host VPC for east-west; spoke egress → hub. |
| 6 | Enable **Private Google Access**; **Private Service Connect** endpoints for Google APIs. |

**Private-only checks:** Org Policy `compute.vmExternalIpAccess` = deny; no external LB; no public IPs; APIs via PSC + restricted VIP (`199.36.153.4/30` private path).

---

## Guardrails

Preventive controls applied at the org container, so every new spoke is non-public by default (the
cross-cloud control matrix is in [doc 04](../architecture/04-security-baseline.md#1-control-matrix)).

```yaml
# Deny external IPs on all VMs
constraint: constraints/compute.vmExternalIpAccess
listPolicy:
  allValues: DENY

---
# Prevent public access to Cloud Storage buckets
constraint: constraints/storage.publicAccessPrevention
booleanPolicy:
  enforced: true

---
# Restrict resource locations to the chosen region
constraint: constraints/gcp.resourceLocations
listPolicy:
  allowedValues:
    - in:europe-west1-locations

---
# Disable default network (forces explicit, private VPC design)
constraint: constraints/compute.skipDefaultNetworkCreation
booleanPolicy:
  enforced: true
```

Pair with: **Private Google Access** + **Private Service Connect** for Google APIs, deny external
forwarding rules, VPC Service Controls perimeter around data services, and Security Command Center
for detection.

---

## Cost

Fixed monthly platform cost for the production design, list price (the roll-up with colo, data
transfer and scenarios is in [doc 07](../architecture/07-cost-estimate.md#5-roll-up)).

| Item | Unit | Qty | Monthly |
|------|------|-----|---------|
| Dedicated Interconnect port 10 Gbps | ~$1,700/link | 2 (redundancy) | $3,400 |
| VLAN attachments | capacity-based | 2 | ~$60 |
| Cloud Router / BGP | free | — | $0 |
| Private Service Connect endpoints | $0.01/hr (~$7.3) | ~6 | $44 |
| Cloud DNS (zones + queries) | low | — | ~$20 |
| **GCP fixed subtotal** | | | **≈ $3,520** |

> **GCP dominates** because **Dedicated Interconnect's minimum port is 10 Gbps** (~$1,700 each, ×2
> for redundancy). If you need <10 Gbps, **Partner Interconnect** (50 Mbps–10 Gbps) is dramatically
> cheaper and is the single biggest lever on the whole estimate — see [doc 07 §6](../architecture/07-cost-estimate.md#6-biggest-levers-how-to-reduce).

---

## PoC

The running PoC (VPN instead of Interconnect, one hub project and one spoke project) and its use
cases are described as one architecture in [README.md](README.md).

---

## Infrastructure as code

| Path | What |
|------|------|
| [`infra/modules/gcp-hub`](../../infra/modules/gcp-hub) | Interconnect, Cloud Router, Shared VPC / NCC, Cloud DNS |
| [`infra/modules/gcp-spoke`](../../infra/modules/gcp-spoke) | Service project attached to the Shared VPC |
| [`infra/stacks/gcp`](../../infra/stacks/gcp) | Production landing-zone stack (GCS backend, `TODO` values) |
| [`infra/policy/gcp`](../../infra/policy/gcp) | The Org Policy constraints above |
| [`infra/stacks/gcp-poc`](../../infra/stacks/gcp-poc) | The running PoC (GCS state `mini-cloud-499820-tfstate`): [`gcp-vpn-poc`](../../infra/modules/gcp-vpn-poc), [`gcp-poc-spoke`](../../infra/modules/gcp-poc-spoke), [`gcp-poc-spoke-sharedvpc`](../../infra/modules/gcp-poc-spoke-sharedvpc), [`gcp-stt-poc`](../../infra/modules/gcp-stt-poc) |
