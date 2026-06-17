# Infrastructure as Code — Skeleton

Terraform skeleton for the hybrid multi-cloud hub-and-spoke described in [`../docs`](../docs/README.md).
This is a **structure + pattern** scaffold, not a turnkey deployment — resource bodies are
representative and marked `# TODO` where environment-specific values are required.

## Layout

```
infra/
├── README.md
├── policy/                 # guardrails as code (doc 04)
│   ├── aws-scp.tf          # Service Control Policies
│   └── gcp-org-policy.tf   # Organization Policy constraints
├── modules/
│   ├── aws-hub/            # Tier-2 hub: Direct Connect GW, TGW, Network Firewall, resolvers
│   ├── aws-spoke/          # workload VPC attached to TGW, default route -> firewall
│   ├── azure-hub/          # ExpressRoute GW, hub VNet, Azure Firewall, Private DNS Resolver
│   └── gcp-hub/            # Interconnect, Cloud Router, Shared VPC / NCC, Cloud DNS
├── onprem/                # PoC on-prem VPN endpoint (strongSwan + FRR configs)
└── stacks/
    ├── aws/               # composition: hub + N spokes for one cloud
    ├── azure/
    ├── gcp/
    └── gcp-poc/           # VPN PoC (doc 08): LAN <-> GCP over IPsec, local state
```

## PoC variant (VPN instead of dedicated circuits)

For a cheap proof-of-concept, [`modules/gcp-vpn-poc`](modules/gcp-vpn-poc) + [`stacks/gcp-poc`](stacks/gcp-poc)
stand up a LAN↔GCP **site-to-site VPN** (HA VPN + BGP) with a no-external-IP test VM, paired with the
on-prem [`onprem/`](onprem/README.md) strongSwan+FRR config. This **overrides decision D1** for the
PoC only — see [docs/08-poc-vpn.md](../docs/08-poc-vpn.md).

## Conventions

- **One root stack per cloud** (`stacks/aws`, add `stacks/azure`, `stacks/gcp`) — separate state,
  separate provider credentials, no cross-cloud provider in a single apply.
- CIDRs come from the IPAM plan in [doc 02 §1](../docs/02-network-design.md). Pass supernets in via
  variables; never hardcode in modules.
- ASN plan ([doc 02 §3](../docs/02-network-design.md)): on-prem `65000`, AWS TGW `65010`, GCP Cloud
  Router `65020`, Azure ExpressRoute MS-side fixed `12076`.
- Guardrails in `policy/` deploy **first**, at the org container, so spokes are non-public by default.

## Apply order

1. `policy/` (org-wide guardrails).
2. `stacks/<cloud>` hub.
3. `stacks/<cloud>` spokes.
4. DNS resolvers + forwarders (within hub module).

## Backend

Each stack ships a `backend.tf` with the right backend type (S3+DynamoDB / azurerm / GCS) and
`TODO` placeholders for the pre-created state bucket/account + lock. Fill them, then `terraform init`.

## Workflow

```
make fmt            # format all .tf
make validate       # offline: init -backend=false + validate every stack & policy
make plan STACK=aws # plan one stack (needs creds + filled tfvars/backend)
make plan-all       # plan all three
```

CI ([`.github/workflows/terraform.yml`](../.github/workflows/terraform.yml)) runs `fmt -check` and
`validate` on every push/PR — both offline, no cloud credentials. `plan`/`apply` are deliberately
left to a credentialed environment (they need real state + provider auth).
