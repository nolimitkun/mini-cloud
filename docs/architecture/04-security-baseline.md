# Security Baseline — Guardrails as Code

**Status:** Draft v0.1 — derives from [01-architecture-specification.md](01-architecture-specification.md)
**Enforces:** C1 (no public IPs), C2 (no Internet egress), G2 (no public exposition).

Guardrails are **preventive** (deny at the control plane) first, **detective** (config rules /
policy audit) second. They are applied at the **org container** so every new spoke account /
subscription / project is non-public by default (Tier-2 landing zone, [01 §3.4](01-architecture-specification.md)).

> The snippets below are illustrative policy bodies, not a full IaC repo. They go in version
> control and deploy via the org's pipeline (Terraform / CloudFormation StackSets / Bicep / gcloud).

---

## 1. Control matrix

| Control | AWS | Azure | GCP |
|---------|-----|-------|-----|
| No public IP on compute | SCP deny `RunInstances` w/ public IP; deny EIP | Policy deny `publicIPAddresses` | Org Policy `compute.vmExternalIpAccess` |
| No Internet gateway | SCP deny `CreateInternetGateway`, `CreateEgressOnlyIGW` | Policy deny route to Internet next-hop | Org Policy `compute.skipDefaultNetworkCreation` + deny default routes |
| No public load balancer | SCP deny public scheme ELBv2 | Policy deny public Standard LB / App GW public | Org Policy deny external forwarding rules |
| No public PaaS endpoint | Condition: require VPC endpoint policies | Policy require Private Endpoint; deny public network access | Org Policy `restrictPublicIp` on services; PSC only |
| Restrict regions | SCP `aws:RequestedRegion` allow-list | Policy `allowedLocations` | Org Policy `gcp.resourceLocations` |
| Block public object storage | SCP deny public S3 / account-level BPA | Policy deny blob public access | Org Policy `storage.publicAccessPrevention` |
| Require encryption in transit | Endpoint/TLS policy | Policy require HTTPS / secure transfer | Org Policy + service config |

---

## 2. AWS — Service Control Policies (SCP)

SCPs at the OU holding every workload and network account: deny internet gateways, public IPs,
Elastic IPs, internet-facing load balancers, and regions other than `eu-west-1`. Policy body and
detective rules: [AWS — guardrails](../aws/README.md#guardrails).

---

## 3. Azure — Azure Policy (assigned at Management Group)

Azure Policy at the Management Group: deny public IPs and public PaaS access, require Private
Endpoints, allow only `westeurope`. Policy body and assignments:
[Azure — guardrails](../azure/README.md#guardrails).

---

## 4. GCP — Organization Policy (at the org / folder)

Org Policy at the org or folder: deny VM external IPs, enforce storage public-access prevention,
restrict locations to `europe-west1`, skip the default network. Constraints:
[GCP — guardrails](../gcp/README.md#guardrails).

---

## 5. Cross-cutting controls

| Area | Control |
|------|---------|
| Identity | Central IdP (OIDC/SAML) federated to all clouds; no standing long-lived keys; short-lived STS/SAS/OIDC tokens. |
| Egress | Default-deny; OS/package updates via on-prem mirror or private endpoints only (C2). |
| Encryption | MACsec on circuits where available; IPsec fallback; mTLS/TLS at app layer (NFR3). |
| Logging | Cloud-native audit logs (CloudTrail / Activity Log / Cloud Audit Logs) shipped to a central, private SIEM over the circuit. |
| Inspection | East-west via cloud hub firewall + on-prem NGFW (D2); deny-by-default rule base. |
| Drift | Detective rules (Config / Policy / SCC) alert on any public-exposure drift; auto-remediate where safe. |

---

## 6. Validation

- [ ] New account/subscription/project inherits all guardrails with **zero manual steps**.
- [ ] Attempt to create a public IP / IGW / public LB / public bucket → **denied**.
- [ ] PaaS resource created with public access → **denied** (Private Endpoint/PSC required).
- [ ] Resource in a non-approved region → **denied**.
- [ ] Detective rules fire on simulated drift; alerts reach the SIEM.

---

## 7. Next

- `05-dns-design.md` — detailed zones, forwarders, resolver rules (optional deepen).
- IaC repo skeleton: `hub/`, `spokes/aws|azure|gcp/`, `policy/` modules.
