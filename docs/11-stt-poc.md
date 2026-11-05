# Speech-to-Text and Text-to-Speech from On-Prem (Chirp 3 via LiteLLM)

On-prem applications transcribe audio with Google's **Chirp 3** model without calling the public
internet and without a service-account key. The on-prem side is the
[mini-platform](https://github.com/nolimitkun/mini-platform-deployment) Kubernetes cluster, whose
**LiteLLM** gateway exposes Chirp 3 as an ordinary OpenAI-style model, `chirp-3`. The same path
serves the reverse direction: `tts-chirp-3-hd` speaks text with Google's Chirp 3 HD voices.

```
client (Open WebUI, kagent, curl …) with a LiteLLM key
  → LiteLLM   POST /v1/audio/transcriptions  model=chirp-3
       pod token ──STS──▶ short-lived token for litellm-stt@  (no key file)
  → eu-speech.googleapis.com   (cluster DNS → 10.48.64.2)
  → IPsec tunnel → PSC endpoint for Google APIs in vpc-poc
  → Speech-to-Text v2, location eu, model chirp_3

client → LiteLLM   POST /v1/audio/speech  model=tts-chirp-3-hd  voice=en-US-Chirp3-HD-Charon
  → eu-texttospeech.googleapis.com  → same DNS, tunnel and PSC endpoint
  → Text-to-Speech v1 text:synthesize
```

## Pieces

| Where | What | Why |
|-------|------|-----|
| `gcp-vpn-poc` | `google_compute_global_address` + `google_compute_global_forwarding_rule` (`all-apis`) at **10.48.64.2** | A private IP for every `*.googleapis.com` API inside the hub VPC. Private Google Access only serves VMs; hybrid clients need this endpoint. The IP comes from the GCP private-endpoint block (doc 02 §1.3). |
| `gcp-vpn-poc` | Cloud Router advertises `10.48.64.2/32` (mode becomes `CUSTOM` + `ALL_SUBNETS`) | So FRR on-prem learns a route to it over `ipsec0`. |
| `gcp-stt-poc` | `speech`, `texttospeech`, `sts`, `iamcredentials` APIs; SA `litellm-stt` with `speech.client` + `serviceUsageConsumer` | The SA can only transcribe and synthesize. Text-to-Speech has no IAM permission of its own; LiteLLM bills the hub project (`x-goog-user-project`), hence the second role. |
| `gcp-stt-poc` | Project-level `gcp.resourceLocations` policy: inherit the org's list, add `eu` | The org allows only `europe-west1`, where Chirp 3 doesn't run. The exception covers the hub only; without it Google answers `FAILED_PRECONDITION … violates constraint`. |
| `gcp-stt-poc` | Workload identity pool `onprem-k8s`, OIDC provider `minikube` | Trusts the cluster's service-account tokens. Its issuer (`https://kubernetes.default.svc.cluster.local`) isn't reachable from Google, so the public keys are uploaded (`onprem-k8s-jwks.json`). The attribute condition accepts only `system:serviceaccount:mini-platform:litellm`. |
| `gcp-stt-poc` | `roles/iam.workloadIdentityUser` on `litellm-stt` for that one subject | Lets the LiteLLM pod impersonate the SA. |
| on-prem host | nftables source rewrite in `ipsec-xfrm.sh` | Without it, traffic into the tunnel leaves as `169.254.0.2`, which GCP can't reply to. |
| mini-platform-deployment | `chirp-3` and `tts-chirp-3-hd` models, `litellm` ServiceAccount, projected token, `scripts/gcp-psc-dns.sh` | The client side: token, credential config and DNS. |

## Google APIs

All in the hub project (`mini-cloud-499820`). The `gcp-stt-poc` module enables the first four, with
`disable_on_destroy = false`, so removing the module leaves them on.

| API | Enabled by | Used for |
|-----|------------|----------|
| `speech.googleapis.com` | `gcp-stt-poc` | Speech-to-Text v2 `recognize`, model `chirp_3`, location `eu` |
| `texttospeech.googleapis.com` | `gcp-stt-poc` | Text-to-Speech `text:synthesize`, called on the `eu-texttospeech` endpoint |
| `sts.googleapis.com` | `gcp-stt-poc` | Trades the pod's Kubernetes token for a federated Google token |
| `iamcredentials.googleapis.com` | `gcp-stt-poc` | Trades that for a one-hour token for `litellm-stt` |
| `iam.googleapis.com` | `gcp-stt-poc`, `infra/ci/setup-plan-identity.sh` | The pool, provider and SA; the CI plan job bills the hub, so it needs this to read them |
| `compute.googleapis.com` | already on, **not managed by Terraform** | PSC endpoint, Cloud VPN, Cloud Router |
| `orgpolicy.googleapis.com` | already on, **not managed by Terraform** | The `eu` location exception |

The last two predate this work. A fresh hub project needs them enabled by hand before the first
apply. No billing API (`cloudbilling`, `billingbudgets`) is enabled; budgets and billing export
aren't set up.

## How the keyless login works

It's the same federation as the GitHub workflows (doc 09), with Kubernetes as the identity
provider:

1. The kubelet mounts a service-account token into the LiteLLM pod, at
   `/var/run/secrets/gcp-wif/token`, minted for the pool's audience and rotated before it expires.
2. LiteLLM's credential config (`type: external_account`, terraform output
   `stt_credential_config`) tells google-auth to send that token to `sts.googleapis.com`. GCP checks
   the signature against the uploaded keys and the subject against the condition.
3. google-auth trades the federated token at `iamcredentials.googleapis.com` for a one-hour access
   token for `litellm-stt`, and LiteLLM calls Speech-to-Text or Text-to-Speech with it.

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

curl -s localhost:4000/v1/audio/speech -H "Authorization: Bearer $KEY" -H 'Content-Type: application/json' \
  -d '{"model":"tts-chirp-3-hd","input":"Bonjour depuis le cloud.","voice":"fr-FR-Chirp3-HD-Aoede","response_format":"mp3"}' \
  -o bonjour.mp3
```

Feeding the MP3 back to `chirp-3` is a quick round trip check.

`sudo tcpdump -ni ipsec0 host 10.48.64.2` shows the request leaving through the tunnel.

## Limits and upkeep

- **One minute, 10 MB per request.** LiteLLM uses the synchronous `recognize` method. Longer audio
  has to be split into clips; Chirp 3's `BatchRecognize` is not wired up.
- **Locations.** Chirp 3 is GA only in `us` and `eu`; `eu` keeps the audio in Europe, and the
  hub's location exception allows only that. Another location needs both the exception widened and
  its hostname (`us-speech.googleapis.com`) added to `gcp-psc-dns.sh`.
- **Recreated cluster.** New signing keys: run `infra/onprem/refresh-k8s-jwks.sh` and commit the
  JSON, or every token exchange fails with `invalid_grant`.
- **Voices.** `tts-chirp-3-hd` needs a Google voice name (`<lang>-Chirp3-HD-<voice>`); the OpenAI
  names (`alloy`, `nova` …) fall back to older WaveNet voices. The language comes from the name.
- **Tunnel down = no speech.** Cluster DNS sends the four API names only to the PSC IP. Run
  `scripts/gcp-psc-dns.sh --remove` to fall back to the public endpoints. The keyless login still
  works that way, since the APIs are public, only the private path is lost.
- **Cost.** See [Cost](#cost).

## Cost

Billed to the hub project. List prices in USD; check the
[Speech-to-Text](https://cloud.google.com/speech-to-text/pricing) and
[VPC](https://cloud.google.com/vpc/network-pricing#psc-forwarding-rules) pricing pages before budgeting.

| Item | Price | Monthly at test volume |
|------|-------|------------------------|
| PSC endpoint for Google APIs (added here) | $0.01 per hour | ≈ $7.30 |
| PSC data processing | none: a global Google APIs endpoint has no data charge | $0 |
| Chirp 3 transcription (added here) | $0.016 per minute (standard v2 recognition, first 500k min/month) | 2-second clip ≈ $0.0005; 1,000 min ≈ $16 |
| Chirp 3 HD speech (added here) | $30 per 1M characters, first 1M characters a month free | ≈ $0 within the free tier; a 1,000-word page ≈ $0.18 beyond it |
| Cloud VPN tunnel (already there, doc 08) | $0.05 per hour × 1 tunnel | ≈ $36.50 |
| Replies back over the tunnel | internet egress rates (the peer is outside Google) | ≈ $0, text only |
| STS, IAM Credentials, pool, SA, location policy, Cloud Router | free | $0 |

So this use case adds about **$7–8 a month fixed** plus the per-minute and per-character speech charges, and the fixed
part doesn't grow with traffic. Two figures are unconfirmed: Google's page lists $0.016/min for
standard v2 recognition, and that Chirp 3 has no premium comes from third-party sources; the Chirp 3 HD
voice rate also comes from a third-party summary of Google's
[Text-to-Speech pricing](https://cloud.google.com/text-to-speech/pricing).
LiteLLM charges the same rate on its side: `litellm_spend_metric_total` recorded $0.00053 for the
2-second test.

### Watching usage

- **LiteLLM (Prometheus/Grafana in mini-platform):** `litellm_proxy_total_requests_metric_total`
  by `requested_model` (`chirp-3`, `tts-chirp-3-hd`) and `status_code`, `litellm_llm_api_latency_metric`,
  `litellm_spend_metric_total`. Traces go to Tempo and Langfuse.
- **Google (Cloud Monitoring, free):** `serviceruntime.googleapis.com/api/request_count` for
  `speech.googleapis.com` (method `Speech.Recognize`) and `texttospeech.googleapis.com`, by response
  code.
- No dashboard, alert or budget exists yet for either model.
