# AWS

AWS is one of the three cloud spokes of the on-prem hub: a Transit Gateway landing zone in
`eu-west-1`, reached over Direct Connect, with AWS services consumed through PrivateLink only.

**Status:** Terraform written and validated offline; not deployed. Account ids, circuit ids and the state backend are `TODO` placeholders.

← [Project overview](../../README.md) · [Shared design](../README.md) · [AWS](../aws/README.md) · [Azure](../azure/README.md) · [GCP](../gcp/README.md)

---

## Landing zone

| Layer | AWS construct |
|-------|---------------|
| Org / tenancy | Organizations + Control Tower |
| Cloud hub (Tier-2 hub) | Network account: **Transit Gateway** + Direct Connect Gateway |
| Inspection | **AWS Network Firewall** in an inspection VPC |
| Shared services | Central VPC: Route 53 Resolver, PrivateLink (interface/gateway) endpoints |
| Workload spokes | Workload accounts: spoke VPCs → TGW attachment, default route → firewall |
| Guardrails | SCPs at OU level |

## Addressing and routing

| Item | Value |
|------|-------|
| Region | `eu-west-1` |
| Private supernet | `10.16.0.0/12` (hub `10.16.0.0/20`, prod `10.16.16.0/20`, non-prod `10.16.32.0/20`, shared `10.16.48.0/20`, endpoints `10.16.64.0/20`) |
| Cross-cloud block | `172.17.0.0/16` |
| BGP | TGW ASN `65010` ↔ on-prem `65000` over the Transit VIF |
| DNS | Route 53 Resolver inbound + outbound endpoints; private hosted zones for `aws.corp.internal` and `privatelink.*` |

The full plan is in [doc 02](../architecture/02-network-design.md) and [doc 05](../architecture/05-dns-design.md).

---

## Connectivity build

Production build steps for the private circuit and the cloud hub (the shared sequence and colo edge
are in [doc 03](../architecture/03-connectivity-buildout.md)).

| Step | Action |
|------|--------|
| 1 | Order **Dedicated Direct Connect** (1–10 Gbps) at the AWS DX location matching the colo; 2× for redundancy. |
| 2 | Create the **LAG** (optional) and the **Transit VIF** associated with the Direct Connect Gateway. |
| 3 | Create **Transit Gateway** (ASN `65010`) in the network account; associate the DX Gateway. |
| 4 | eBGP `65000 ↔ 65010` over each transit VIF; enable BFD; advertise `10.16.0.0/12` to on-prem. |
| 5 | TGW route tables: on-prem `10.0.0.0/12` + approved cross-cloud prefixes via DX; spokes → inspection VPC. |
| 6 | Build **inspection VPC** with AWS Network Firewall; default route from spokes → firewall (D2). |

**Private-only checks:** no Public VIF; no IGW in any VPC; AWS service access via **interface/gateway VPC endpoints** (S3, ECR, STS, SSM, etc.) in the shared-services spoke.

---

## Guardrails

Preventive controls applied at the org container, so every new spoke is non-public by default (the
cross-cloud control matrix is in [doc 04](../architecture/04-security-baseline.md#1-control-matrix)).

Attach at the OU that contains all workload + network accounts.

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "DenyInternetGateways",
      "Effect": "Deny",
      "Action": [
        "ec2:CreateInternetGateway",
        "ec2:AttachInternetGateway",
        "ec2:CreateEgressOnlyInternetGateway"
      ],
      "Resource": "*"
    },
    {
      "Sid": "DenyPublicIPOnLaunch",
      "Effect": "Deny",
      "Action": "ec2:RunInstances",
      "Resource": "arn:aws:ec2:*:*:instance/*",
      "Condition": { "Bool": { "ec2:AssociatePublicIpAddress": "true" } }
    },
    {
      "Sid": "DenyElasticIPs",
      "Effect": "Deny",
      "Action": ["ec2:AllocateAddress", "ec2:AssociateAddress"],
      "Resource": "*"
    },
    {
      "Sid": "DenyPublicLoadBalancers",
      "Effect": "Deny",
      "Action": "elasticloadbalancing:CreateLoadBalancer",
      "Resource": "*",
      "Condition": { "StringEquals": { "elasticloadbalancing:Scheme": "internet-facing" } }
    },
    {
      "Sid": "RestrictRegions",
      "Effect": "Deny",
      "NotAction": ["iam:*", "organizations:*", "route53:*", "cloudfront:*", "sts:*"],
      "Resource": "*",
      "Condition": { "StringNotEquals": { "aws:RequestedRegion": ["eu-west-1"] } }
    }
  ]
}
```

Pair with **account-level S3 Block Public Access**, VPC endpoint policies for AWS service access,
and AWS Config rules (`vpc-no-internet-gateway`, `ec2-instance-no-public-ip`, `s3-bucket-public-read-prohibited`) for detection.

---

## Cost

Fixed monthly platform cost for the production design, list price (the roll-up with colo, data
transfer and scenarios is in [doc 07](../architecture/07-cost-estimate.md#5-roll-up)).

| Item | Unit | Qty | Monthly |
|------|------|-----|---------|
| Direct Connect dedicated port 1 Gbps | $0.30/hr | 2 | $438 |
| Transit Gateway attachments | $0.0365/hr (~$36.5) | 4 (hub+3 spokes) | $146 |
| AWS Network Firewall endpoint | $0.395/hr (~$288) | 2 AZ | $576 |
| Route 53 Resolver endpoints (ENI) | $0.125/hr (~$91) | 4 (2 in + 2 out) | $365 |
| Interface (PrivateLink) endpoints | $0.01/hr (~$7.3) | ~6 svc × 2 AZ ≈ 12 | $88 |
| **AWS fixed subtotal** | | | **≈ $1,610** |

---

## VPN PoC

A cheap stand-in for Direct Connect: the same LAN-as-on-prem host as the
[GCP VPN PoC](../gcp/vpn-poc.md), with an AWS **Site-to-Site VPN** (virtual private gateway, two
tunnels) and dynamic BGP `65000 ↔ 65010`. Workloads keep no public IP; the VPN endpoint is the only
public address. PoC VPC `10.16.0.0/24`.

**On-prem deltas (strongSwan + FRR):**

- Add one `connections {}` block per tunnel in `swanctl.conf`, each with its own remote peer IP and
  PSK, and a distinct `if_id`, so each gets its own XFRM interface: `ipsec1` and `ipsec2` (`if_id`
  43 and 44; GCP uses `ipsec0`/42, Azure `ipsec3`/45). Run `ipsec-xfrm.sh` once per `if_id`.
- AWS hands back two tunnels with assigned inside `/30`s: read `terraform output` for
  `tunnel1_cgw_inside_address` / `tunnel1_vgw_inside_address` and add an FRR `neighbor` (remote-as
  `65010`) per tunnel, peering the VGW inside address.

> Bring up one cloud at a time and verify with the GCP PoC's
> [verification sequence](../gcp/vpn-poc.md#6-verification) before adding the next.

---

## Infrastructure as code

| Path | What |
|------|------|
| [`infra/modules/aws-hub`](../../infra/modules/aws-hub) | Direct Connect Gateway, TGW, Network Firewall, Route 53 Resolver |
| [`infra/modules/aws-spoke`](../../infra/modules/aws-spoke) | Workload VPC attached to the TGW, default route → firewall |
| [`infra/stacks/aws`](../../infra/stacks/aws) | Production landing-zone stack (S3 backend, `TODO` values) |
| [`infra/policy/aws`](../../infra/policy/aws) | The SCPs above |
| [`infra/modules/aws-vpn-poc`](../../infra/modules/aws-vpn-poc), [`infra/stacks/aws-poc`](../../infra/stacks/aws-poc) | VPN PoC |
