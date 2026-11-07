# Infrastructure as Code — Skeleton

Terraform skeleton for the hybrid multi-cloud hub-and-spoke described in [`../docs`](../docs/README.md).
This is a **structure + pattern** scaffold, not a turnkey deployment — resource bodies are
representative and marked `# TODO` where environment-specific values are required.

## Layout

```
infra/
├── README.md
├── policy/                 # guardrails as code (doc 04) — separate per cloud (separate creds)
│   ├── aws/aws-scp.tf      # Service Control Policies
│   └── gcp/                # Organization Policy constraints (+ provider, tfvars example)
│                           # (no Azure policy code yet: doc only)
├── modules/
│   ├── aws-hub/            # Tier-2 hub: Direct Connect GW, TGW, inspection VPC + Network Firewall
│   │                       #   (transit VIFs, Route 53 Resolver endpoints: TODO stubs)
│   ├── aws-spoke/          # workload VPC attached to TGW, default route -> firewall
│   ├── azure-hub/          # ExpressRoute GW, hub VNet, Azure Firewall, Private DNS Resolver (inbound)
│   ├── azure-spoke/        # workload VNet peered to the hub, UDR -> firewall
│   ├── gcp-hub/            # Shared VPC host, Interconnect attachments, Cloud Router, deny-egress firewall
│   ├── gcp-spoke/          # service project attached to the Shared VPC
│   ├── gcp-vpn-poc/        # PoC hub: VPC, HA VPN + Cloud Router, PSC endpoints, firewall, test VMs
│   ├── gcp-poc-spoke/      # PoC: VPC-peered spoke project + test VM
│   ├── gcp-poc-spoke-sharedvpc/  # PoC: Shared-VPC spoke + lakehouse (GCS managed folders + Iceberg REST catalog)
│   ├── gcp-stt-poc/        # PoC: speech/Gemini APIs, litellm-stt SA, on-prem workload identity pool
│   ├── aws-vpn-poc/        # PoC: AWS Site-to-Site VPN (VGW), dynamic BGP
│   └── azure-vpn-poc/      # PoC: Azure route-based VPN Gateway, static routing
├── onprem/                 # PoC on-prem VPN endpoint (strongSwan + FRR configs, helper scripts)
├── diagram/                # live-diagram generator (Inframap + Graphviz, docs/gcp/live-diagram.md)
├── ci/                     # one-time setup of the keyless GitHub identities (plan + diagram jobs)
└── stacks/
    ├── aws/  azure/  gcp/  # production landing-zone stacks (hub + spokes)
    ├── gcp-poc/            # the running GCP PoC: VPN, spoke, lakehouse, speech (GCS remote state)
    │   └── scripts/        # lakehouse seeder (sample Iceberg tables via the runtime catalog)
    ├── aws-poc/            # VPN PoC: LAN <-> AWS Site-to-Site VPN
    └── azure-poc/          # VPN PoC: LAN <-> Azure VPN Gateway
```

## PoC variant (VPN instead of dedicated circuits)

For a cheap proof-of-concept, the `*-vpn-poc` modules + `*-poc` stacks stand up a LAN↔cloud
**site-to-site VPN** (GCP HA VPN + BGP, AWS Site-to-Site VPN + BGP, Azure route-based VPN + static),
paired with the on-prem [`onprem/`](onprem/README.md) strongSwan+FRR config. This **overrides
decision D1** for the PoC only — see [docs/gcp/hub-connectivity.md](../docs/gcp/hub-connectivity.md)
(AWS and Azure variants in [docs/aws](../docs/aws/README.md#vpn-poc) and
[docs/azure](../docs/azure/README.md#vpn-poc)). Only the GCP PoC is deployed.

## Conventions

- **One root stack per cloud** (`stacks/aws`, `stacks/azure`, `stacks/gcp`) — separate state,
  separate provider credentials, no cross-cloud provider in a single apply.
- CIDRs come from the IPAM plan in [doc 02 §1](../docs/architecture/02-network-design.md). Pass supernets in via
  variables; never hardcode in modules.
- ASN plan ([doc 02 §3](../docs/architecture/02-network-design.md)): on-prem `65000`, AWS TGW `65010`, GCP Cloud
  Router `65020`, Azure ExpressRoute MS-side fixed `12076`.
- Guardrails in `policy/` deploy **first**, at the org container, so spokes are non-public by default.

## Apply order

1. `policy/` (org-wide guardrails).
2. `stacks/<cloud>` hub.
3. `stacks/<cloud>` spokes.
4. DNS resolvers + forwarders (planned inside the hub modules; only Azure's inbound resolver
   exists so far).

## Backend

The production stacks ship a `backend.tf` with the right backend type (S3+DynamoDB / azurerm /
GCS) and `TODO` placeholders for the pre-created state bucket/account + lock. Fill them, then
`terraform init`. `stacks/gcp-poc` uses a real GCS backend (`mini-cloud-499820-tfstate`);
`stacks/aws-poc` and `stacks/azure-poc` have no backend and keep local state.

## Workflow

```
make fmt            # format all .tf
make validate       # offline: init -backend=false + validate every stack & policy
make plan STACK=aws # plan one stack (needs creds + filled tfvars/backend)
make plan-all       # plan the three production stacks
make diagram        # regenerate docs/diagrams/live-gcp-poc.svg from state (docs/gcp/live-diagram.md)
make apply-poc      # apply stacks/gcp-poc, then refresh the live diagram
make seed-lakehouse # seed sample Iceberg tables via the runtime catalog (docs/gcp/spoke-lakehouse.md)
```

CI, in `.github/workflows/`:

- [`terraform.yml`](../.github/workflows/terraform.yml) runs `fmt -check` and `validate` on every
  push/PR that touches `infra/`, offline, with no cloud credentials.
- [`terraform-plan.yml`](../.github/workflows/terraform-plan.yml) runs a real `terraform plan` of
  `stacks/gcp-poc` on PRs, keylessly as the read-only `tf-plan-ci` SA, and posts only resource
  addresses and actions (the repo is public).
- [`diagram.yml`](../.github/workflows/diagram.yml) regenerates the live diagram on pushes to `main`.

Nothing in CI applies; `apply` is run by hand from a credentialed machine.
