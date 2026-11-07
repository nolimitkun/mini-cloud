# Documentation

The design for the hybrid multi-cloud hub-and-spoke: the on-prem private cloud is the hub, and AWS,
Azure and GCP are spokes, connected over private circuits only. The
[project README](../README.md) has the overview, the high-level schema and the cloud comparison.

The docs are split in two:
- `architecture/` holds the cloud-neutral design that applies to every provider.
- One folder per cloud holds what is specific to that provider, including the PoCs.

## Shared design (`architecture/`)

Read in order:

| # | Doc | Covers |
|---|-----|--------|
| 01 | [Architecture specification](architecture/01-architecture-specification.md) | Goals, requirements, topology, two-tier hub-and-spoke, decisions |
| 02 | [Network design](architecture/02-network-design.md) | IPAM and CIDR planes, BGP and ASNs, route tables, east-west, resilience |
| 03 | [Connectivity buildout](architecture/03-connectivity-buildout.md) | Build sequence, colo edge, DNS and endpoints, acceptance tests |
| 04 | [Security baseline](architecture/04-security-baseline.md) | Control matrix and cross-cutting controls |
| 05 | [DNS design](architecture/05-dns-design.md) | Namespace, resolvers, forwarding, split-horizon |
| 06 | [Buildout runbook](architecture/06-buildout-runbook.md) | Phased, checkbox execution plan with gates |
| 07 | [Cost estimate](architecture/07-cost-estimate.md) | Colo, data transfer, roll-up, scenarios, savings levers |

## Per cloud

| Cloud | Landing zone, circuit build, guardrails, cost | PoCs |
|-------|-----------------------------------------------|------|
| [AWS](aws/README.md) | Transit Gateway, Direct Connect, SCPs | [Site-to-Site VPN](aws/README.md#vpn-poc) (Terraform only) |
| [Azure](azure/README.md) | Hub VNet, ExpressRoute, Azure Policy | [VPN Gateway](azure/README.md#vpn-poc) (Terraform only) |
| [GCP](gcp/landing-zone.md) | Shared VPC / NCC, Cloud Interconnect, Org Policy | Running, as [one hub-and-spoke](gcp/README.md): [connectivity](gcp/hub-connectivity.md), [lakehouse](gcp/spoke-lakehouse.md), [speech and Gemini](gcp/hub-ai-services.md), [live diagram](gcp/live-diagram.md) |

**Diagrams:** the [diagram gallery](diagrams/README.md) has the topology, landing zone, east-west
inspection, buildout phases, cost breakdown, PoC and lakehouse diagrams. All docs embed them from
`diagrams/`.

## Infrastructure as code

[`../infra`](../infra/README.md) holds the Terraform:
- Per-cloud landing-zone modules (`hub` + `spoke` for AWS, Azure and GCP).
- Composition stacks (`stacks/aws|azure|gcp`).
- The PoC stacks.
- The guardrail policies.

Circuit ids, project and subscription ids, and the production state backends are `# TODO`
placeholders.

## Open items

1. Controlled Internet egress — fully air-gapped vs. a single audited on-prem egress path.
2. Circuit redundancy depth — dual POPs per provider from day one vs. phased.
