# DNS Design

**Status:** Draft v0.1 — derives from [01](01-architecture-specification.md), [02 §2](02-network-design.md)
**Principle:** the on-prem hub owns the authoritative private namespace; each cloud resolves locally
and forwards across the private circuits. No public DNS is used for internal names; no internal
record is published to a public resolver.

---

## 1. Namespace

| Zone | Authority | Use |
|------|-----------|-----|
| `corp.internal` | On-prem | Root private namespace; on-prem hosts, services |
| `aws.corp.internal` | AWS (Route 53 private) | AWS workloads + private endpoints |
| `azure.corp.internal` | Azure (Private DNS) | Azure workloads + Private Endpoints |
| `gcp.corp.internal` | GCP (Cloud DNS private) | GCP workloads + PSC endpoints |
| Provider PaaS zones | Provider-managed private | e.g. `privatelink.*`, `privatelink.blob.core.windows.net`, `*.run.app` (PSC) |

Delegation: on-prem `corp.internal` conditionally forwards each `<cloud>.corp.internal` subdomain to
that cloud's inbound resolver; each cloud forwards `corp.internal` (and the other clouds' subdomains,
when an east-west flow is approved) back to on-prem.

---

## 2. Resolver placement

Every **cloud hub** ([01 §3.4](01-architecture-specification.md)) runs resolver endpoints in its `10.x.0.0/20` block:

| Cloud | Inbound (others → cloud) | Outbound (cloud → others) | Private zones |
|-------|--------------------------|---------------------------|---------------|
| AWS | Route 53 Resolver **inbound endpoint** | Route 53 Resolver **outbound endpoint** + rules | Route 53 **private hosted zones**, `privatelink.*` |
| Azure | **Private DNS Resolver** inbound endpoint | Private DNS Resolver outbound + forwarding ruleset | **Private DNS zones** linked to hub VNet |
| GCP | Cloud DNS **inbound forwarding** entry point | Cloud DNS **outbound forwarding** zones | Cloud DNS **private zones** |

Each resolver is deployed across **≥ 2 AZs** (no single resolver SPOF, NFR matching [02 §5](02-network-design.md)).

---

## 3. Forwarding rules

| Query origin | Name pattern | Forward to |
|--------------|--------------|------------|
| On-prem | `aws.corp.internal` | AWS inbound resolver IPs (`10.16.0.x`) |
| On-prem | `azure.corp.internal` | Azure inbound resolver IPs (`10.32.0.x`) |
| On-prem | `gcp.corp.internal` | GCP inbound resolver IPs (`10.48.0.x`) |
| AWS | `corp.internal` | On-prem resolver IPs (`10.0.0.x`) |
| Azure | `corp.internal` | On-prem resolver IPs |
| GCP | `corp.internal` | On-prem resolver IPs |
| Any cloud | other cloud's subdomain | **Only when east-west flow approved** → on-prem → target cloud |

Cross-cloud DNS, like cross-cloud data, defaults to **no path** — it is enabled per approved flow,
keeping the hub-and-spoke boundary in DNS as well as routing.

---

## 4. Private endpoints & split-horizon

- A private endpoint (PrivateLink / Private Endpoint / PSC) auto-registers an A record into the
  provider's private zone (e.g. `privatelink.blob.core.windows.net` → `10.32.64.x`).
- Those zones are linked to the cloud hub and resolvable from on-prem and (when allowed) other clouds
  via the forwarders above — so a workload always gets the **private IP**, never a public one.
- Public DNS for the same service name is never consulted from inside the network (split-horizon):
  egress to public resolvers is denied (C2), and conditional forwarders intercept the PaaS names.
- **Two-plane endpoints ([02 §1](02-network-design.md)):** an endpoint consumed only intra-cloud /
  from on-prem registers its **private-plane** address (`10.x.64.0/20`); an endpoint consumed across
  clouds registers a **cross-cloud-plane** address (`172.x.64.0/24`). The provider private zone
  returns whichever applies, so a cross-cloud consumer resolves the `172` address and reaches it over
  the cross-cloud plane — no `10`-space route is ever needed off-cloud.

---

## 5. Failure behavior

- Resolver endpoints are multi-AZ; loss of one AZ keeps resolution up.
- Loss of a circuit to a cloud → that cloud's subdomain becomes unresolvable from on-prem (expected;
  the cloud is isolated by design). Local resolution within the isolated cloud still works.
- No fallback to public DNS — that would violate G2; isolation is preferred over leaking to public.

---

## 6. Validation

- [ ] `corp.internal` resolves from every cloud; each `<cloud>.corp.internal` resolves from on-prem.
- [ ] A PaaS private endpoint resolves to its **private** IP from on-prem and allowed clouds.
- [ ] Public resolver queries from a spoke are **blocked** (no `8.8.8.8` / public DNS path).
- [ ] Cross-cloud name resolution is denied unless the flow is explicitly approved.
