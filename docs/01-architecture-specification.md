# Hybrid Multi-Cloud Architecture — Specification

**Status:** Draft v0.1
**Owner:** Platform / Network Engineering
**Date:** 2026-06-17

---

## 1. Purpose & Scope

Define a **hybrid, multi-cloud** architecture where an **on-premises private cloud** acts as the
**hub** and the three public cloud providers (**AWS, Azure, GCP**) act as **spokes**, connected over
**private circuits only**. No cloud workload or platform service is reachable from the public
Internet, and no traffic between sites traverses the public Internet.

### 1.1 Goals

- **G1 — Private-only data plane.** All inter-site traffic flows over private connections (no Internet path).
- **G2 — No public exposition.** Cloud services (compute, data, PaaS) expose **no public IPs / public endpoints**.
- **G3 — Hub-and-spoke topology.** On-prem is the central hub; each cloud is a spoke. Spoke-to-spoke
  transit is mediated, not implicit.
- **G4 — Provider parity.** AWS, Azure, GCP are integrated with equivalent patterns, not bespoke per cloud.
- **G5 — Centralized control.** Routing, DNS, identity, and security policy are governed centrally.

### 1.2 Non-Goals

- Public-facing web hosting / CDN (would be a separate, isolated DMZ design).
- Application-level design (this document is network + platform topology only).
- Migration sequencing (covered in a later runbook).

### 1.3 Definitions

| Term | Meaning |
|------|---------|
| Hub | On-prem private cloud + colocation edge that aggregates all connectivity. |
| Spoke | A single cloud provider's landing zone (AWS / Azure / GCP). |
| Cloud Exchange | Neutral L2/L3 fabric (e.g. Equinix Fabric, Megaport, PacketFabric) used to reach providers privately. |
| Private endpoint | Provider construct exposing a PaaS service via a private IP inside the customer network (PrivateLink / Private Endpoint / PSC). |

---

## 2. Requirements

### 2.1 Functional

- **F1** On-prem hub terminates private circuits to AWS, Azure, and GCP.
- **F2** Each spoke reaches the hub; spoke→spoke traffic transits the hub (or a controlled transit tier).
- **F3** PaaS/data services in each cloud are consumed via **private endpoints** only.
- **F4** Unified private DNS resolution across on-prem and all three clouds.
- **F5** Dynamic routing (BGP) with deterministic, non-overlapping addressing.

### 2.2 Non-Functional

| ID | Requirement | Target |
|----|-------------|--------|
| NFR1 | Circuit availability | ≥ 99.9% per provider (dual circuits, dual POPs) |
| NFR2 | Hub↔Spoke latency | ≤ 10 ms within region pairing |
| NFR3 | Encryption in transit | MACsec on circuit where available; IPsec/TLS app-layer always |
| NFR4 | RTO (network path) | ≤ 15 min via redundant path failover (BGP) |
| NFR5 | Throughput | Sized per circuit (start 1–10 Gbps, scalable) |

### 2.3 Constraints

- **C1 — No public IPs** on any cloud resource (enforced by policy / SCP / Azure Policy / Org Policy).
- **C2 — No Internet egress** from spokes except via controlled, on-prem-routed proxy (default deny).
- **C3 — Non-overlapping RFC1918 space** across on-prem and all clouds (strict IPAM).

---

## 3. Logical Architecture

### 3.1 Topology

```
                         ┌─────────────────────────────┐
                         │     ON-PREM PRIVATE CLOUD    │
                         │            (HUB)             │
                         │  • Core routing / BGP        │
                         │  • Central firewall / NGFW   │
                         │  • DNS resolver / IPAM       │
                         │  • Identity (IdP) / PKI      │
                         └───────────────┬─────────────┘
                                         │
                              ┌──────────┴──────────┐
                              │   COLOCATION EDGE    │
                              │  Cloud Exchange (L2/ │
                              │  L3 fabric) + routers│
                              └───┬──────┬──────┬────┘
                Direct Connect│   ExpressRoute│  Cloud Interconnect│
                              │              │                    │
                    ┌─────────▼───┐  ┌───────▼─────┐  ┌───────────▼─┐
                    │   AWS spoke │  │ Azure spoke │  │  GCP spoke  │
                    │ Transit GW  │  │ vWAN/vNet   │  │ NCC / VPC   │
                    │ + VPCs      │  │   hub       │  │  hub        │
                    │ PrivateLink │  │ PrivateEP   │  │  PSC        │
                    └─────────────┘  └─────────────┘  └─────────────┘
```

### 3.2 Per-provider private connectivity

| Provider | Private circuit | In-cloud hub | Private service access |
|----------|-----------------|--------------|------------------------|
| AWS | **Direct Connect** (Dedicated/Hosted) + Transit VIF | **Transit Gateway** + spoke VPCs | **PrivateLink / VPC endpoints** |
| Azure | **ExpressRoute** (private peering) | **Virtual WAN** or hub VNet + peering | **Private Endpoint / Private Link** |
| GCP | **Cloud Interconnect** (Dedicated/Partner) | **Network Connectivity Center** + Shared VPC | **Private Service Connect** |

### 3.3 Hub-and-spoke enforcement

- Spokes have **no transit attachment to each other**. Default route in each spoke points to the
  hub (or in-cloud hub which forwards to on-prem / inspection tier).
- Spoke-to-spoke ("multi-cloud east-west") is **explicitly allowed flows only**, hairpinned through
  the inspection tier (on-prem NGFW or a cloud firewall in the in-cloud hub).
- No spoke advertises another spoke's routes directly — the hub owns route propagation.

### 3.4 Two-tier (nested) hub-and-spoke — cloud landing zones

The topology is hub-and-spoke at **two levels**:

- **Tier 1 (inter-cloud):** on-prem is the global hub; each cloud is a spoke (Section 3.1–3.3).
- **Tier 2 (intra-cloud):** inside each cloud, a **landing zone** is itself a hub-and-spoke. A
  central **connectivity / hub network** is the regional hub; **workload spokes** (one per
  app/environment) attach to it. The cloud hub is the single point where the private circuit, the
  cloud firewall, DNS resolvers, and shared private endpoints live.

The cloud hub thus has **two roles**: it is a *spoke* to the on-prem hub, and a *hub* to its own
workload spokes. Workload spokes never connect to the circuit, to the Internet, or to each other
directly — all transit and inspection passes through the cloud hub.

#### Landing-zone construct per provider

| Layer | AWS | Azure | GCP |
|-------|-----|-------|-----|
| Org / tenancy | Organizations + Control Tower | Management Groups + subscriptions | Org + folders + projects |
| Cloud hub (Tier-2 hub) | Network account: **Transit Gateway** + circuit attach | Connectivity subscription: **hub VNet** + ExpressRoute GW | Host project: **Shared VPC** + NCC + Interconnect attach |
| Inspection | AWS Network Firewall in hub | **Azure Firewall** in hub VNet | Firewall / NVA in host VPC |
| Shared services | Central VPC: Route 53 Resolver, PrivateLink endpoints | Hub: Private DNS Resolver, Private Endpoints | Host project: Cloud DNS, PSC endpoints |
| Workload spokes | Workload accounts: spoke VPCs → TGW attachment | Workload subscriptions: spoke VNets → VNet peering | Service projects: attached to Shared VPC |
| Guardrails | SCPs at OU level | Azure Policy at MG level | Org Policy at folder level |

#### Tier-2 enforcement

- Default route of every workload spoke → cloud hub (`0.0.0.0/0` and on-prem summary via hub).
- Workload spokes get **no direct peering to each other** — east-west hairpins through the cloud
  hub firewall (matches D2 hybrid inspection).
- Only the cloud hub holds the gateway/transit attachment to the private circuit; spokes inherit
  reachability through it (transitive routing via TGW / peering with UDR / NCC).
- Landing-zone guardrails (SCP / Azure Policy / Org Policy) are applied at the org container so
  every new spoke account/subscription/project is non-public **by default**.

---

## 4. Addressing & DNS

### 4.1 IP Address Management (IPAM)

- Single authoritative IPAM; allocate **non-overlapping** supernets:
  - On-prem: `10.0.0.0/12`
  - AWS: `10.16.0.0/12`
  - Azure: `10.32.0.0/12`
  - GCP: `10.48.0.0/12`
  - Reserved/transit/PaaS: `10.64.0.0/12`
- Summarizable per-region blocks to keep BGP tables small.

### 4.2 DNS

- **Central private DNS** authority on-prem; each cloud runs an inbound/outbound resolver:
  - AWS **Route 53 Resolver** endpoints (inbound + outbound + rules).
  - Azure **Private DNS Resolver** + Private DNS zones linked to hub VNet.
  - GCP **Cloud DNS** private zones + inbound/outbound forwarding.
- Conditional forwarding: on-prem → cloud private zones, and cloud → on-prem for internal names.
- Private endpoints register into provider private zones, resolvable from all sites.

---

## 5. Security

- **Zero public exposure:** policy guardrails block public IP assignment and Internet gateways.
  - AWS: SCPs deny `igw`, public ELB, public subnets; VPC endpoints for AWS APIs.
  - Azure: Azure Policy denies public IP, requires Private Endpoint; no public PaaS.
  - GCP: Org Policy `constraints/compute.vmExternalIpAccess` = deny; Private Google Access.
- **Inspection tier:** centralized NGFW (on-prem) and/or cloud-native firewall in each in-cloud hub
  for east-west and any controlled egress.
- **Encryption:** MACsec on circuits where supported; IPsec overlay as fallback; mTLS/TLS at app layer.
- **Identity:** central IdP (SAML/OIDC) federated to each cloud; no standing long-lived cloud creds.
- **Egress:** default-deny; package mirrors / updates via on-prem proxy or private mirrors only.

---

## 6. Resilience

- **Dual circuits** per provider, terminating on **two diverse colo POPs / devices**.
- **BGP** with path preference + BFD for sub-second failure detection.
- In-cloud hubs deployed across **≥ 2 availability zones**.
- Tested failover runbooks (NFR4).

---

## 7. Decisions (Locked v0.1)

| # | Decision | Choice | Rationale |
|---|----------|--------|-----------|
| D1 | Circuit topology | **Dedicated circuits per provider** | Lowest latency & per-Mbps cost at scale; direct DX/ExpressRoute/Interconnect to each provider POP. Accept longer lead times and more cross-connects. |
| D2 | Inspection placement | **Hybrid** | Cloud-native firewall in each in-cloud hub handles intra-cloud + cloud↔cloud east-west; on-prem NGFW inspects anything touching on-prem. Balances latency vs. central control. |
| D3 | Region scope | **Single region per cloud** | Simpler CIDR/routing/DNS to start; multi-region is an additive change later. |
| D4 | In-cloud hub products | AWS Transit Gateway; Azure hub VNet (vWAN optional later); GCP NCC + Shared VPC | Self-managed where it preserves routing control. |

### 7.1 Still open

1. **Controlled Internet egress** — fully air-gapped, or a single audited egress path on-prem?
2. **Circuit redundancy depth** — dual POPs per provider from day one vs. phased.

---

## 8. Next Artifacts

- `02-network-design.md` — CIDR plan, BGP/ASN scheme, route tables, failover.
- `03-connectivity-buildout.md` — circuit ordering, colo, per-provider steps.
- `04-security-baseline.md` — guardrail policies (SCP / Azure Policy / Org Policy) as code.
- `05-dns-design.md` — zones, forwarders, resolver rules.
- Diagrams as code (`.drawio` / Mermaid) + optional Terraform skeleton.
