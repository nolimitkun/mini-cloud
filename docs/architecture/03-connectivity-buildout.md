# Connectivity Buildout

**Status:** Draft v0.1 — derives from [01-architecture-specification.md](01-architecture-specification.md), [02-network-design.md](02-network-design.md)
**Decisions:** dedicated circuits per provider (D1), single region per cloud (D3).

This is the physical + provider build order to stand up the private circuits and Tier-2 cloud hubs.
Nothing here exposes a public endpoint; every step keeps the data plane private.

---

## 1. Build sequence (high level)

1. Colocation footprint + edge routers.
2. Cross-connects ordered to each provider's on-ramp.
3. Layer-2 circuits provisioned (DX / ExpressRoute / Interconnect).
4. Cloud-side gateways + BGP brought up (Layer-3).
5. Tier-2 landing-zone hubs built; spokes attached.
6. DNS resolvers + private endpoints.
7. Validation against the [§6 checklist](02-network-design.md).

Order matters: lead times for cross-connects and dedicated ports (weeks) dominate, so order
**circuits first**, build cloud config in parallel while waiting.

---

## 2. Colocation edge

- **Two diverse cages/POPs** (or two devices in one cage minimum) for circuit diversity (NFR1).
- Edge routers run the on-prem routing domain ASN `65000`, terminate all eBGP sessions, host BFD.
- Cross-connects (single-mode fiber) ordered from the colo provider to each cloud on-ramp panel.
- MACsec enabled on cross-connects where the provider and optics support it (NFR3); IPsec overlay
  as fallback on circuits without MACsec.

| Item | Quantity | Notes |
|------|----------|-------|
| Colo cross-connect → AWS on-ramp | 2 | One per Direct Connect circuit |
| Colo cross-connect → Azure on-ramp | 2 | ExpressRoute primary + secondary |
| Colo cross-connect → GCP on-ramp | 2 | Two Interconnect circuits |

---

## 3. AWS — Direct Connect → Transit Gateway

Two Dedicated Direct Connect circuits with a Transit VIF into a Direct Connect Gateway, a Transit Gateway
(ASN `65010`) and an inspection VPC with AWS Network Firewall. Step by step:
[AWS — connectivity build](../aws/README.md#connectivity-build).

---

## 4. Azure — ExpressRoute → hub VNet

An ExpressRoute circuit with private peering only, an ExpressRoute Gateway and Azure Firewall in the
hub VNet, spokes peered with a default route to the firewall. Step by step:
[Azure — connectivity build](../azure/README.md#connectivity-build).

---

## 5. GCP — Cloud Interconnect → Shared VPC / NCC

Dedicated Interconnect with two VLAN attachments, Cloud Router (ASN `65020`), a Shared VPC host
project as cloud hub (plus NCC if multi-VPC) and PSC for Google APIs. Step by step:
[GCP — connectivity build](../gcp/README.md#connectivity-build).

---

## 6. DNS & endpoints (after L3 is up)

- Deploy resolver endpoints in each cloud hub (Route 53 Resolver / Private DNS Resolver / Cloud DNS).
- Conditional forwarders both directions (see [02 §2](02-network-design.md)).
- Register private endpoints into provider private zones; verify cross-cloud resolution via on-prem.

---

## 7. Acceptance tests

- [ ] BGP up + BFD up on all 6 circuits; failover drill passes (pull primary, traffic holds).
- [ ] Each cloud reachable from on-prem; cloud→cloud blocked unless explicitly allowed.
- [ ] No public IP resolves anywhere; `curl` to any cloud public endpoint from a spoke fails.
- [ ] Provider API calls succeed via private endpoints only (public API path blocked).
- [ ] Private DNS resolves on-prem ↔ each cloud ↔ private endpoints.

---

## 8. Next

- `04-security-baseline.md` — guardrails as code that enforce the private-only checks above.
