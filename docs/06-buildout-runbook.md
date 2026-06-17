# Buildout Runbook

**Status:** Draft v0.1 — operational companion to [03-connectivity-buildout.md](03-connectivity-buildout.md)
**Audience:** the engineer(s) executing the build, step by step.

This is the ordered, checkbox runbook. Each phase has an **owner**, **lead time**, **pre-reqs**, and
a **done-when** gate. Do not start a phase until its pre-reqs are green. Times are wall-clock; many
phases run in parallel (see the dependency note in each).

> Legend: ☐ not started · ⧗ ordered/in-flight · ✅ done-when gate passed

---

## Phase 0 — Foundations (week 0)

| # | Task | Owner | Done-when |
|---|------|-------|-----------|
| 0.1 | Ratify IPAM plan; lock supernets in authoritative IPAM | Network | No overlaps; recorded in IPAM tool |
| 0.2 | Decide the two open items: egress model, dual-POP timing ([01 §7.1](01-architecture-specification.md)) | Architecture | Documented decision |
| 0.3 | Stand up Terraform state backends (per stack) | Platform | `terraform init` succeeds in each stack |
| 0.4 | Deploy org guardrails (`infra/policy/`) **before any spoke** | Security | Attempt to create a public IP is denied in each cloud |

**Gate:** guardrails proven (0.4) — nothing non-public can be created from here on.

---

## Phase 1 — Order circuits (week 0, long lead) ⧗

Order **first**; everything physical waits on these. Build cloud config (Phase 3) in parallel.

| # | Task | Lead time | Done-when |
|---|------|-----------|-----------|
| 1.1 | Order colo cross-connects ×6 (2 per provider) | 1–3 wk | Cross-connect IDs issued |
| 1.2 | Order **AWS Dedicated Direct Connect** ×2 | 2–6 wk | LOA-CFA received, port live |
| 1.3 | Order **Azure ExpressRoute** circuit (private peering) | 2–6 wk | Service key, provider status = provisioned |
| 1.4 | Order **GCP Dedicated Interconnect** ×2 | 2–6 wk | Interconnect + LOA issued |

**Gate:** all six L1/L2 circuits show "up" at the colo and provider portals.

---

## Phase 2 — Colo edge (parallel with Phase 1 tail)

| # | Task | Done-when |
|---|------|-----------|
| 2.1 | Rack/configure edge routers in two diverse POPs; ASN `65000` | Routers reachable, config baselined |
| 2.2 | Patch cross-connects; light fiber to each provider on-ramp | Optical light levels in spec |
| 2.3 | Enable MACsec where supported; else stage IPsec overlay | Link encryption confirmed |

**Gate:** L1/L2 up end-to-end colo↔provider for all six.

---

## Phase 3 — Cloud Tier-2 hubs (parallel with Phases 1–2)

Run `infra/stacks/<cloud>` **hub** module. Per-cloud detail in [03 §3–5](03-connectivity-buildout.md).

| # | Task | Cloud | Done-when |
|---|------|-------|-----------|
| 3.1 | `terraform apply` hub (TGW + DX GW + Network Firewall + resolvers) | AWS | Apply clean; TGW + DXGW present |
| 3.2 | `terraform apply` hub (ERGW + hub VNet + Azure Firewall + resolver) | Azure | Apply clean; gateway provisioned |
| 3.3 | `terraform apply` hub (Shared VPC + Cloud Router + attachments) | GCP | Apply clean; router up |

**Gate:** each cloud hub exists and is ready to accept BGP + spoke attachments.

---

## Phase 4 — Bring up BGP (needs Phases 2 + 3)

| # | Task | Done-when |
|---|------|-----------|
| 4.1 | AWS: create Transit VIF; eBGP `65000↔65010`; enable BFD | Session established, BFD up |
| 4.2 | Azure: link ExpressRoute connection; eBGP `65000↔12076` primary+secondary | Both sessions up |
| 4.3 | GCP: router interfaces + peers per attachment; eBGP `65000↔65020` | Both sessions up |
| 4.4 | Verify each cloud advertises **one summary** (`10.x.0.0/12`); on-prem does **not** cross-leak | Route tables match [02 §3.3](02-network-design.md) |

**Gate:** on-prem ↔ each cloud reachable; cloud↔cloud **not** reachable (correct default).

---

## Phase 5 — Spokes (needs Phase 4)

Run `infra/stacks/<cloud>` **spoke** instances (prod, nonprod, shared).

| # | Task | Done-when |
|---|------|-----------|
| 5.1 | Apply spokes; attach to hub (TGW / VNet peering / Shared VPC) | Attachments active |
| 5.2 | Confirm default route `0.0.0.0/0` → hub firewall in every spoke | Route present; verified |
| 5.3 | Confirm no spoke↔spoke path (intra-cloud) without firewall | Direct test fails as expected |

**Gate:** a workload in a spoke reaches on-prem via the hub firewall; peers only through inspection.

---

## Phase 6 — DNS & private endpoints (needs Phase 5)

| # | Task | Done-when |
|---|------|-----------|
| 6.1 | Deploy resolver endpoints + forwarders both directions ([05](05-dns-design.md)) | Forwarders active |
| 6.2 | Create representative private endpoints (storage/secrets) per cloud | Endpoints `Approved` |
| 6.3 | Verify PaaS names resolve to **private** IPs from on-prem and allowed clouds | `dig` returns 10.x |

**Gate:** [05 §6](05-dns-design.md) validation passes.

---

## Phase 7 — Verification & sign-off

Run the combined acceptance suite ([02 §6](02-network-design.md), [03 §7](03-connectivity-buildout.md), [04 §6](04-security-baseline.md), [05 §6](05-dns-design.md)):

- [ ] No public IP / IGW / public LB / public PaaS resolvable or creatable anywhere.
- [ ] Each cloud advertises exactly one summary prefix; no cross-leak.
- [ ] Every spoke default-routes to its hub firewall.
- [ ] **Failover drill:** pull each provider's primary circuit → traffic holds on secondary within BFD window.
- [ ] Cross-cloud flow works **only** when explicitly approved, and is inspected at 3 points.
- [ ] DNS resolves on-prem ↔ each cloud ↔ private endpoints; public DNS path blocked.
- [ ] Audit logs landing in the central private SIEM.

**Sign-off:** Network + Security + Architecture owners approve → architecture is production-ready
for first workload onboarding.

---

## Rollback / safety notes

- Guardrails (Phase 0.4) are deployed first and removed last — never tear them down to "unblock" a build.
- Losing both circuits to one cloud isolates that cloud **by design**; do not add an Internet fallback to recover — restore the circuit.
- Terraform state is per-cloud; a failed apply in one cloud cannot affect another.
