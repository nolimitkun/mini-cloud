# Speech-to-Text from On-Prem (Chirp 3 via LiteLLM)

On-prem applications transcribe audio with Google's **Chirp 3** model without calling the public
internet and without a service-account key. The on-prem side is the
[mini-platform](https://github.com/nolimitkun/mini-platform-deployment) Kubernetes cluster, whose
**LiteLLM** gateway exposes Chirp 3 as an ordinary OpenAI-style model, `chirp-3`.

```
client (Open WebUI, kagent, curl …) with a LiteLLM key
  → LiteLLM   POST /v1/audio/transcriptions  model=chirp-3
       pod token ──STS──▶ short-lived token for litellm-stt@  (no key file)
  → eu-speech.googleapis.com   (cluster DNS → 10.48.64.2)
  → IPsec tunnel → PSC endpoint for Google APIs in vpc-poc
  → Speech-to-Text v2, location eu, model chirp_3
```

## Pieces

| Where | What | Why |
|-------|------|-----|
| `gcp-vpn-poc` | `google_compute_global_address` + `google_compute_global_forwarding_rule` (`all-apis`) at **10.48.64.2** | A private IP for every `*.googleapis.com` API inside the hub VPC. Private Google Access only serves VMs; hybrid clients need this endpoint. The IP comes from the GCP private-endpoint block (doc 02 §1.3). |
| `gcp-vpn-poc` | Cloud Router advertises `10.48.64.2/32` (mode becomes `CUSTOM` + `ALL_SUBNETS`) | So FRR on-prem learns a route to it over `ipsec0`. |
| `gcp-stt-poc` | `speech`, `sts`, `iamcredentials` APIs; SA `litellm-stt` with `speech.client` + `serviceUsageConsumer` | The SA can only transcribe. LiteLLM bills the hub project (`x-goog-user-project`), hence the second role. |
| `gcp-stt-poc` | Workload identity pool `onprem-k8s`, OIDC provider `minikube` | Trusts the cluster's service-account tokens. Its issuer (`https://kubernetes.default.svc.cluster.local`) isn't reachable from Google, so the public keys are uploaded (`onprem-k8s-jwks.json`). The attribute condition accepts only `system:serviceaccount:mini-platform:litellm`. |
| `gcp-stt-poc` | `roles/iam.workloadIdentityUser` on `litellm-stt` for that one subject | Lets the LiteLLM pod impersonate the SA. |
| on-prem host | nftables source rewrite in `ipsec-xfrm.sh` | Without it, traffic into the tunnel leaves as `169.254.0.2`, which GCP can't reply to. |
| mini-platform-deployment | `chirp-3` model, `litellm` ServiceAccount, projected token, `scripts/gcp-psc-dns.sh` | The client side: token, credential config and DNS. |

## How the keyless login works

It's the same federation as the GitHub workflows (doc 09), with Kubernetes as the identity
provider:

1. The kubelet mounts a service-account token into the LiteLLM pod, at
   `/var/run/secrets/gcp-wif/token`, minted for the pool's audience and rotated before it expires.
2. LiteLLM's credential config (`type: external_account`, terraform output
   `stt_credential_config`) tells google-auth to send that token to `sts.googleapis.com`. GCP checks
   the signature against the uploaded keys and the subject against the condition.
3. google-auth trades the federated token at `iamcredentials.googleapis.com` for a one-hour access
   token for `litellm-stt`, and LiteLLM calls Speech-to-Text with it.

The credential config holds no secret, which is why it can live in Git.

## Bring-up

```bash
# 1. GCP (from infra/stacks/gcp-poc)
terraform plan && terraform apply

# 2. On-prem host: rebuild ipsec0 with the source rewrite, then restart FRR
sudo apt-get install -y nftables              # if not already installed
sudo install -m 0755 infra/onprem/strongswan/ipsec-xfrm.sh /usr/local/sbin/mini-cloud-ipsec-xfrm.sh
sudo install -m 0644 infra/onprem/systemd/mini-cloud-vpn.service /etc/systemd/system/
sudo systemctl daemon-reload && sudo systemctl restart mini-cloud-vpn frr

# 3. Cluster DNS (from mini-platform-deployment): pin the API names to the PSC endpoint
scripts/gcp-psc-dns.sh 10.48.64.2
```

Then merge the mini-platform-deployment change; Argo CD rolls LiteLLM with the new model.

## Verify

```bash
ip route get 10.48.64.2                       # via 169.254.0.1 dev ipsec0
sudo nft list table ip mini_cloud_vpn         # snat to the LAN address

KEY=$(kubectl -n mini-platform get secret litellm-master-key -o jsonpath='{.data.PROXY_MASTER_KEY}' | base64 -d)
kubectl -n mini-platform port-forward svc/litellm 4000:4000 &
curl -s localhost:4000/v1/audio/transcriptions -H "Authorization: Bearer $KEY" \
  -F model=chirp-3 -F file=@sample.wav -F language=fr-FR
```

`sudo tcpdump -ni ipsec0 host 10.48.64.2` shows the request leaving through the tunnel.

## Limits and upkeep

- **One minute, 10 MB per request.** LiteLLM uses the synchronous `recognize` method. Longer audio
  has to be split into clips; Chirp 3's `BatchRecognize` is not wired up.
- **Locations.** Chirp 3 is GA only in `us` and `eu`; `eu` keeps the audio in Europe. Another
  location needs its hostname (`us-speech.googleapis.com`) added to `gcp-psc-dns.sh`.
- **Recreated cluster.** New signing keys: run `infra/onprem/refresh-k8s-jwks.sh` and commit the
  JSON, or every token exchange fails with `invalid_grant`.
- **Tunnel down = no STT.** Cluster DNS sends the three API names only to the PSC IP. Run
  `scripts/gcp-psc-dns.sh --remove` to fall back to the public endpoints. The keyless login still
  works that way, since the APIs are public, only the private path is lost.
- **Cost.** A PSC endpoint for Google APIs plus Chirp 3 per second of audio; both are small at test
  volume.
