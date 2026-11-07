# Azure

Azure is one of the three cloud spokes of the on-prem hub: a hub-VNet landing zone in West Europe,
reached over ExpressRoute private peering, with PaaS consumed through Private Endpoints only.

**Status:** Terraform written and validated offline; not deployed. Subscription ids, circuit ids and the state backend are `TODO` placeholders.

← [Project overview](../../README.md) · [Shared design](../README.md) · [AWS](../aws/README.md) · [Azure](README.md) · [GCP](../gcp/README.md)

---

## Landing zone

| Layer | Azure construct |
|-------|-----------------|
| Org / tenancy | Management Groups + subscriptions |
| Cloud hub (Tier-2 hub) | Connectivity subscription: **hub VNet** + ExpressRoute Gateway (or Virtual WAN) |
| Inspection | **Azure Firewall** in the hub VNet |
| Shared services | Hub: Private DNS Resolver, Private Endpoints |
| Workload spokes | Workload subscriptions: spoke VNets peered to the hub, UDR `0.0.0.0/0` → firewall |
| Guardrails | Azure Policy at Management Group level |

## Addressing and routing

| Item | Value |
|------|-------|
| Region | `westeurope` |
| Private supernet | `10.32.0.0/12` (hub `10.32.0.0/20`, prod `10.32.16.0/20`, non-prod `10.32.32.0/20`, shared `10.32.48.0/20`, endpoints `10.32.64.0/20`) |
| Cross-cloud block | `172.18.0.0/16` |
| BGP | Microsoft-fixed `12076` ↔ on-prem `65000` over private peering (primary + secondary) |
| DNS | Private DNS Resolver inbound + outbound with a forwarding ruleset; Private DNS zones linked to the hub VNet for `azure.corp.internal` and `privatelink.*` |

The full plan is in [doc 02](../architecture/02-network-design.md) and [doc 05](../architecture/05-dns-design.md).

---

## Connectivity build

Production build steps for the private circuit and the cloud hub (the shared sequence and colo edge
are in [doc 03](../architecture/03-connectivity-buildout.md)).

| Step | Action |
|------|--------|
| 1 | Order **ExpressRoute circuit** (Dedicated/port-based) at the peering location matching the colo. |
| 2 | Enable **Azure private peering** only (no Microsoft peering / no public peering). |
| 3 | Deploy **ExpressRoute Gateway** in the hub VNet (connectivity subscription). |
| 4 | eBGP customer `65000 ↔ 12076` (MS fixed) on primary + secondary; advertise `10.32.0.0/12`. |
| 5 | Deploy **Azure Firewall** in the hub VNet; spoke VNets peered to hub with UDR `0.0.0.0/0` → firewall. |
| 6 | Disable gateway-transit leakage that would allow spoke↔spoke without firewall. |

**Private-only checks:** Azure Policy denies Public IP + public PaaS; all PaaS via **Private Endpoint**; storage/key vault firewalls set to deny-public.

---

## Guardrails

Preventive controls applied at the org container, so every new spoke is non-public by default (the
cross-cloud control matrix is in [doc 04](../architecture/04-security-baseline.md#1-control-matrix)).

```json
{
  "policyRule": {
    "if": {
      "anyOf": [
        { "field": "type", "equals": "Microsoft.Network/publicIPAddresses" },
        {
          "allOf": [
            { "field": "type", "equals": "Microsoft.Network/networkInterfaces" },
            { "field": "Microsoft.Network/networkInterfaces/ipConfigurations[*].publicIPAddress.id", "exists": "true" }
          ]
        }
      ]
    },
    "then": { "effect": "deny" }
  }
}
```

Add the built-in / custom assignments:

- **Deny public network access on PaaS** — Storage, Key Vault, SQL, Cosmos: `publicNetworkAccess = Disabled`, require **Private Endpoint**.
- **Allowed locations** — restrict to `westeurope` (`allowedLocations`).
- **Deny public Standard LB / public App Gateway**.
- **Audit/deny NSG rules allowing `Internet` inbound/outbound** except via the hub firewall.

Detection: Azure Policy compliance dashboard + Defender for Cloud recommendations.

---

## Cost

Fixed monthly platform cost for the production design, list price (the roll-up with colo, data
transfer and scenarios is in [doc 07](../architecture/07-cost-estimate.md#5-roll-up)).

| Item | Unit | Qty | Monthly |
|------|------|-----|---------|
| ExpressRoute circuit, Standard metered 1 Gbps | port fee | 1 (redundant pair built-in) | $436 |
| ExpressRoute Gateway (ErGw1AZ) | ~$0.42/hr | 1 | $310 |
| Azure Firewall (Standard) | $1.25/hr | 1 | $912 |
| Private DNS Resolver (inbound endpoint) | ~$0.27/hr | 1–2 | $200 |
| Private Endpoints | $0.01/hr (~$7.3) | ~6 | $44 |
| **Azure fixed subtotal** | | | **≈ $1,900** |

---

## VPN PoC

A cheap stand-in for ExpressRoute: the same LAN-as-on-prem host as the
[GCP VPN PoC](../gcp/hub-connectivity.md), with a **route-based VPN Gateway** (VpnGw1) and **static** routing
(the LAN is the local network gateway). Workloads keep no public IP; the gateway is the only public
address. PoC VNet `10.32.0.0/24`.

**On-prem deltas (strongSwan):**

- Add one `connections {}` block in `swanctl.conf` with the gateway's public IP and PSK, and its own
  `if_id` 45, so it gets XFRM interface `ipsec3` (GCP uses `ipsec0`/42, AWS `ipsec1`/`ipsec2`). Run
  `ipsec-xfrm.sh` for that `if_id`.
- Static routing (no FRR neighbor): a route for `10.32.0.0/24` via `ipsec3`. BGP over VPN (APIPA
  peers) can be added later to match the GCP and AWS paths.

> Azure VPN Gateway takes about 20–45 minutes to provision. Verify with the GCP PoC's
> [verification sequence](../gcp/hub-connectivity.md#6-verification).

---

## Infrastructure as code

| Path | What |
|------|------|
| [`infra/modules/azure-hub`](../../infra/modules/azure-hub) | ExpressRoute Gateway, hub VNet, Azure Firewall (rule collections `TODO`), Private DNS Resolver with an inbound endpoint only |
| [`infra/modules/azure-spoke`](../../infra/modules/azure-spoke) | Workload VNet peered to the hub |
| [`infra/stacks/azure`](../../infra/stacks/azure) | Production landing-zone stack (azurerm backend, `TODO` values) |
| [`infra/modules/azure-vpn-poc`](../../infra/modules/azure-vpn-poc), [`infra/stacks/azure-poc`](../../infra/stacks/azure-poc) | VPN PoC |

The Azure Policy assignments above are documented only; there is no `infra/policy/azure` yet.
