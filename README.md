# Hybrid Multi-Cloud (Hub-and-Spoke)

A reference design + IaC skeleton for a **hybrid, multi-cloud** architecture:

- **On-prem private cloud is the hub**; **AWS, Azure, GCP are spokes**.
- **Private circuits only** (Direct Connect / ExpressRoute / Cloud Interconnect) — no public
  Internet on the data plane.
- **No public exposure** — no public IPs, IGWs, or public PaaS endpoints; services reached via
  private endpoints (PrivateLink / Private Endpoint / PSC).
- **Two-tier hub-and-spoke** — on-prem ↔ each cloud (Tier 1), and inside each cloud a landing-zone
  **cloud hub** ↔ its **workload spokes** (Tier 2).
- **Hybrid inspection** — cloud firewall per cloud hub for east-west; on-prem NGFW for anything
  touching on-prem. Cross-cloud traffic hairpins through on-prem (no spoke-to-spoke).

## Locked decisions

| # | Decision | Choice |
|---|----------|--------|
| D1 | Circuit topology | Dedicated circuits per provider |
| D2 | Inspection placement | Hybrid (cloud firewalls + on-prem NGFW) |
| D3 | Region scope | Single region per cloud |
| D4 | In-cloud hubs | AWS TGW · Azure hub VNet · GCP Shared VPC/NCC |

## Repository layout

```
docs/      Design: spec, network, connectivity, security, DNS, buildout runbook (+ index)
infra/     Terraform skeleton: hub+spoke modules ×3 clouds, policy guardrails, stacks, Makefile, CI
```

- **Start here:** [docs/README.md](docs/README.md) — design index and reading order.
- **Build it:** [docs/06-buildout-runbook.md](docs/06-buildout-runbook.md) — phased execution plan.
- **Deploy it:** [infra/README.md](infra/README.md) — modules, stacks, `make` workflow.
- **Try it cheaply (PoC):** [docs/08-poc-vpn.md](docs/08-poc-vpn.md) — LAN as on-prem + site-to-site
  VPN to GCP (no dedicated circuit), with runnable Terraform + strongSwan config.
- **Lakehouse PoC:** [docs/10-lakehouse-poc.md](docs/10-lakehouse-poc.md) — GCS data lake +
  Dataplex Knowledge Catalog + Iceberg Runtime Catalog + BigLake, deployed in the spoke project.

## Quick start (offline checks)

```bash
cd infra
make fmt validate     # format + validate all stacks (no cloud credentials needed)
```

Then per cloud: fill `stacks/<cloud>/terraform.tfvars` (from `.example`) and `backend.tf`, deploy
`policy/` first, then `terraform apply` the stack. See the runbook for ordering and gates.

## Status

Design docs and IaC structure are complete. External identifiers (circuit ids, account/project ids,
state backends) are `# TODO` placeholders — they require ordered circuits and live cloud resources.
Two open items remain: controlled-egress model and dual-POP redundancy timing
([docs/README.md](docs/README.md#open-items)).
