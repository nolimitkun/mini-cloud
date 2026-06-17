# Network Design

**Status:** Draft v0.1 — derives from [01-architecture-specification.md](01-architecture-specification.md)
**Scope:** Single region per cloud (decision D3), dedicated circuits per provider (D1), hybrid inspection (D2).

---

## 1. Addressing (IPAM)

Strict non-overlapping RFC1918. Each site gets a `/12` supernet; within a cloud the `/12` is carved
into a Tier-2 landing zone (hub + workload spokes) plus a reserved block for growth.

### 1.1 Supernets

| Site | Supernet | Addresses | Notes |
|------|----------|-----------|-------|
| On-prem | `10.0.0.0/12` | 10.0–10.15 | Datacenter + colo edge |
| AWS | `10.16.0.0/12` | 10.16–10.31 | eu-west-1 |
| Azure | `10.32.0.0/12` | 10.32–10.47 | West Europe |
| GCP | `10.48.0.0/12` | 10.48–10.63 | europe-west1 |
| Transit / PaaS reserve | `10.64.0.0/12` | 10.64–10.79 | PrivateLink/PE/PSC ranges, future regions |

### 1.2 Per-cloud carve (identical pattern across providers)

Using AWS `10.16.0.0/12` as the worked example; Azure (`10.32`) and GCP (`10.48`) follow the same offsets.

| Block | CIDR (AWS) | Role |
|-------|-----------|------|
| Cloud hub | `10.16.0.0/20` | Connectivity hub (TGW/hub-VNet/Shared-VPC), firewall, DNS, gateways |
| Prod spoke | `10.16.16.0/20` | Production workload VPC/VNet |
| Non-prod spoke | `10.16.32.0/20` | Dev/test workload VPC/VNet |
| Shared-services spoke | `10.16.48.0/20` | Platform services, CI, registries |
| Private-endpoint subnets | `10.16.64.0/20` | PrivateLink / Private Endpoint / PSC NICs |
| Reserved | `10.16.128.0/17` | Future spokes / second AZ expansion |

Each `/20` summarizes cleanly so the cloud hub advertises **one route per cloud** (`10.16.0.0/12`)
toward on-prem, keeping BGP tables small (Section 3.4).

### 1.3 Subnet layout inside a spoke (example, prod `10.16.16.0/20`)

| Subnet | CIDR | AZ | Purpose |
|--------|------|----|---------|
| app-a | `10.16.16.0/24` | az-1 | Application tier |
| app-b | `10.16.17.0/24` | az-2 | Application tier (HA) |
| data-a | `10.16.18.0/24` | az-1 | Private data tier |
| data-b | `10.16.19.0/24` | az-2 | Private data tier (HA) |
| endpoints | `10.16.20.0/24` | az-1/2 | Interface endpoints into this spoke |

No public subnets exist (constraint C1); there is no IGW / public LB / public IP.

---

## 2. DNS resolution

| Direction | Mechanism |
|-----------|-----------|
| On-prem → cloud private zones | Conditional forwarders → cloud inbound resolver endpoints |
| Cloud → on-prem internal names | Outbound resolver rules → on-prem resolvers |
| Cloud → its own private endpoints | Provider private DNS zone, auto-registered |
| Cross-cloud name resolution | Via on-prem authoritative zone (hub owns the namespace) |

Resolver endpoints live in each **cloud hub** (`10.x.0.0/20`): Route 53 Resolver (AWS), Private DNS
Resolver (Azure), Cloud DNS forwarding (GCP).

---

## 3. Routing & BGP

### 3.1 ASN plan (private ASNs)

| Domain | ASN | Role |
|--------|-----|------|
| On-prem core / colo edge | `65000` | Global hub routing domain (customer side of all circuits) |
| AWS Transit Gateway | `65010` | Amazon-side BGP on Direct Connect transit VIF |
| Azure ExpressRoute | MS-fixed `12076` | Microsoft side; customer gateway peers as `65000` |
| GCP Cloud Router | `65020` | GCP side of Cloud Interconnect VLAN attachment |

### 3.2 eBGP sessions

- **On-prem ↔ AWS:** eBGP `65000 ↔ 65010` over Direct Connect transit VIF (dual, one per circuit).
- **On-prem ↔ Azure:** eBGP `65000 ↔ 12076` over ExpressRoute private peering (primary + secondary).
- **On-prem ↔ GCP:** eBGP `65000 ↔ 65020` over two VLAN attachments (Cloud Router HA, two interfaces).
- **BFD** enabled on every session for sub-second liveness.

### 3.3 Advertisements

| From | Advertises | To |
|------|-----------|----|
| On-prem | `10.0.0.0/12` (on-prem) + default-originate (optional, for controlled egress) | All clouds |
| AWS hub | `10.16.0.0/12` (summary) | On-prem |
| Azure hub | `10.32.0.0/12` (summary) | On-prem |
| GCP hub | `10.48.0.0/12` (summary) | On-prem |

- Clouds advertise **summary only** — no per-spoke routes leak across the WAN.
- On-prem **does not redistribute one cloud's summary to another** → enforces no implicit
  spoke-to-spoke (G3). Cross-cloud reachability is added as an *explicit* policy route when a flow
  is approved (Section 4).

### 3.4 In-cloud route tables (Tier-2)

- **Cloud hub** holds the circuit attachment and the inspection firewall. Its route table sends
  `10.0.0.0/12` (on-prem) and any approved cross-cloud prefix out the circuit, and `0.0.0.0/0`
  to the firewall (default-deny egress).
- **Workload spokes** default-route (`0.0.0.0/0`) to the cloud hub firewall via:
  - AWS: spoke VPC route table → TGW attachment; TGW route table → firewall/inspection VPC.
  - Azure: spoke VNet UDR `0.0.0.0/0` → Azure Firewall private IP in hub VNet (peered).
  - GCP: spoke (service project) routes → NCC / Shared-VPC hub; firewall policy on host VPC.
- Transitive spoke→spoke **inside one cloud** is blocked unless hairpinned through the hub firewall.

---

## 4. East-west (cross-cloud) flows

![Cross-cloud east-west hairpins through the on-prem NGFW, inspected three times](diagrams/03-eastwest-inspection.svg)

Cloud-to-cloud traffic is **not** a direct path — there is no spoke-to-spoke and no cloud-to-cloud
peering. An approved flow (e.g. AWS prod → Azure prod) traverses:

```
AWS spoke → AWS hub firewall → Direct Connect → on-prem NGFW
          → ExpressRoute → Azure hub firewall → Azure spoke
```

- Inspected at the **source cloud firewall**, the **on-prem NGFW**, and the **destination cloud
  firewall** (hybrid inspection, D2).
- Enabled by adding the specific destination prefix (e.g. `10.32.16.0/20`) as an explicit route +
  firewall allow-rule on the path — never a blanket cloud-to-cloud route.
- Latency cost is accepted as the trade-off for central control and zero lateral trust.

---

## 5. Resilience

| Layer | Mechanism | Target |
|-------|-----------|--------|
| Circuit | Dual circuits per provider on diverse colo devices/POPs | NFR1 99.9% |
| BGP path | `local-pref` primary, AS-path prepend on secondary; BFD | NFR4 ≤ 15 min (sub-second in practice) |
| Cloud hub | Gateways/firewall across ≥ 2 AZs | AZ-fault tolerant |
| DNS | Redundant resolver endpoints per hub (multi-AZ) | No single resolver SPOF |

### 5.1 Failover behavior

- Primary circuit loss → BGP withdraws, traffic shifts to secondary within BFD detection window.
- Both circuits to one cloud lost → that cloud is isolated (by design — no Internet fallback).
  Monitored and alerted; covered by per-provider dual-POP diversity.

---

## 6. Validation checklist

- [ ] No overlapping CIDR across any site (IPAM authoritative).
- [ ] No public IP / IGW / public PaaS endpoint resolvable anywhere (guardrails, see `04`).
- [ ] Each cloud advertises exactly one summary prefix.
- [ ] On-prem does not transit cloud-A summary to cloud-B by default.
- [ ] Every workload spoke default-routes to its cloud hub firewall.
- [ ] BFD up on all eBGP sessions; failover tested.

---

## 7. Next

- `03-connectivity-buildout.md` — circuit ordering, colo cross-connects, per-provider gateway build.
- `04-security-baseline.md` — SCP / Azure Policy / Org Policy guardrails as code.
