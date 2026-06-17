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

| Step | Action |
|------|--------|
| 3.1 | Order **Dedicated Direct Connect** (1–10 Gbps) at the AWS DX location matching the colo; 2× for redundancy. |
| 3.2 | Create the **LAG** (optional) and the **Transit VIF** associated with the Direct Connect Gateway. |
| 3.3 | Create **Transit Gateway** (ASN `65010`) in the network account; associate the DX Gateway. |
| 3.4 | eBGP `65000 ↔ 65010` over each transit VIF; enable BFD; advertise `10.16.0.0/12` to on-prem. |
| 3.5 | TGW route tables: on-prem `10.0.0.0/12` + approved cross-cloud prefixes via DX; spokes → inspection VPC. |
| 3.6 | Build **inspection VPC** with AWS Network Firewall; default route from spokes → firewall (D2). |

**Private-only checks:** no Public VIF; no IGW in any VPC; AWS service access via **interface/gateway VPC endpoints** (S3, ECR, STS, SSM, etc.) in the shared-services spoke.

---

## 4. Azure — ExpressRoute → hub VNet

| Step | Action |
|------|--------|
| 4.1 | Order **ExpressRoute circuit** (Dedicated/port-based) at the peering location matching the colo. |
| 4.2 | Enable **Azure private peering** only (no Microsoft peering / no public peering). |
| 4.3 | Deploy **ExpressRoute Gateway** in the hub VNet (connectivity subscription). |
| 4.4 | eBGP customer `65000 ↔ 12076` (MS fixed) on primary + secondary; advertise `10.32.0.0/12`. |
| 4.5 | Deploy **Azure Firewall** in the hub VNet; spoke VNets peered to hub with UDR `0.0.0.0/0` → firewall. |
| 4.6 | Disable gateway-transit leakage that would allow spoke↔spoke without firewall. |

**Private-only checks:** Azure Policy denies Public IP + public PaaS; all PaaS via **Private Endpoint**; storage/key vault firewalls set to deny-public.

---

## 5. GCP — Cloud Interconnect → Shared VPC / NCC

| Step | Action |
|------|--------|
| 5.1 | Order **Dedicated Interconnect** at the colocation facility; provision 2× VLAN attachments. |
| 5.2 | Create **Cloud Router** (ASN `65020`) per attachment for HA (two interfaces). |
| 5.3 | eBGP `65000 ↔ 65020`; advertise `10.48.0.0/12`; enable BFD. |
| 5.4 | Host project **Shared VPC** = cloud hub; attach service projects (spokes). Add **NCC** hub if multi-VPC. |
| 5.5 | Firewall policy / NVA in host VPC for east-west; spoke egress → hub. |
| 5.6 | Enable **Private Google Access**; **Private Service Connect** endpoints for Google APIs. |

**Private-only checks:** Org Policy `compute.vmExternalIpAccess` = deny; no external LB; no public IPs; APIs via PSC + restricted VIP (`199.36.153.4/30` private path).

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
