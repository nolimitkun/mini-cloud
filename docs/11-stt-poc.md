# Speech and Gemini from On-Prem (Chirp 3 and Gemini via LiteLLM)

On-prem applications transcribe, speak and chat with Google's speech and Gemini models without
calling the public internet and without a service-account key. The on-prem side is the
[mini-platform](https://github.com/nolimitkun/mini-platform-deployment) Kubernetes cluster, whose
**LiteLLM** gateway exposes each model as an ordinary OpenAI-style model:

| LiteLLM model | OpenAI route | Google model | API, location |
|---------------|--------------|--------------|---------------|
| `chirp-3` | `/v1/audio/transcriptions` | Chirp 3 | Speech-to-Text v2, `eu` |
| `tts-chirp-3-hd` | `/v1/audio/speech` | Chirp 3 HD voices | Cloud Text-to-Speech, `eu` endpoint |
| `gemini-3.8-flash-tts` | `/v1/audio/speech` | Gemini 3.8 Flash TTS | Vertex AI, `eu` multi-region |
| `gemini-3.8-flash-lite-tts` | `/v1/audio/speech` | Gemini 3.8 Flash-Lite TTS | Vertex AI, `eu` multi-region |
| `gemini-live` | `/v1/realtime` (websocket) | Gemini Live 2.5 Flash native audio, live transcription | Vertex AI, `europe-west1` |
| `gemini-4-argon` | `/v1/chat/completions` | Gemini 4 Argon | Vertex AI, `eu` multi-region |
| `gemini-3.8-flash` | `/v1/chat/completions` | Gemini 3.8 Flash | Vertex AI, `eu` multi-region |
| `gemini-3.5-flash` | `/v1/chat/completions` | Gemini 3.5 Flash | Vertex AI, `eu` multi-region |
| `gemini-3.5-flash-lite` | `/v1/chat/completions` | Gemini 3.5 Flash-Lite | Vertex AI, `eu` multi-region |

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

client → LiteLLM   POST /v1/audio/speech  model=gemini-3.8-flash-tts  voice=Kore
  → aiplatform.eu.rep.googleapis.com  (cluster DNS → 10.48.65.2, regional PSC endpoint)
  → Vertex AI generateContent, location eu

client ⇄ LiteLLM   WS /v1/realtime?model=gemini-live   (PCM16 audio in, transcript events out)
  ⇄ europe-west1-aiplatform.googleapis.com  (cluster DNS → 10.48.64.2)
  ⇄ Vertex AI BidiGenerateContent, location europe-west1

client → LiteLLM   POST /v1/chat/completions  model=gemini-4-argon (or a Gemini 3.x Flash)
  → aiplatform.eu.rep.googleapis.com  → same regional PSC endpoint as Gemini TTS
  → Vertex AI generateContent, location eu
```

## Pieces

| Where | What | Why |
|-------|------|-----|
| `gcp-vpn-poc` | `google_compute_global_address` + `google_compute_global_forwarding_rule` (`all-apis`) at **10.48.64.2** | A private IP for every `*.googleapis.com` API inside the hub VPC. Private Google Access only serves VMs; hybrid clients need this endpoint. The IP comes from the GCP private-endpoint block (doc 02 §1.3). |
| `gcp-vpn-poc` | Cloud Router advertises `10.48.64.2/32` (mode becomes `CUSTOM` + `ALL_SUBNETS`) | So FRR on-prem learns a route to it over `ipsec0`. |
| `gcp-vpn-poc` | Subnet `subnet-poc-psc-endpoints` (**10.48.65.0/28**) + `google_network_connectivity_regional_endpoint` `psc-aiplatform-eu` at **10.48.65.2**, target `aiplatform.eu.rep.googleapis.com` | Vertex AI's `eu` multi-region is a two-level `*.eu.rep.googleapis.com` name, which the `all-apis` endpoint's `*.googleapis.com` certificate doesn't cover. A regional endpoint does; `ALL_SUBNETS` advertises its subnet. |
| `gcp-stt-poc` | `speech`, `texttospeech`, `aiplatform`, `sts`, `iamcredentials` APIs; SA `litellm-stt` with `speech.client`, `serviceUsageConsumer` and custom role `litellmVertexCaller` | The SA can only transcribe, synthesize and call Gemini models (`aiplatform.endpoints.predict`; `roles/aiplatform.user` would also let it create and delete Vertex resources). Text-to-Speech has no IAM permission of its own; LiteLLM bills the hub project (`x-goog-user-project`), hence `serviceUsageConsumer`. |
| `gcp-stt-poc` | Project-level `gcp.resourceLocations` policy: inherit the org's list, add `eu` | The org allows only `europe-west1`, where Chirp 3 and the Gemini 3.8 TTS models don't run. The exception covers the hub only; without it Google answers `FAILED_PRECONDITION … violates constraint`. Gemini Live runs in `europe-west1`, which the org already allows. |
| `gcp-stt-poc` | Workload identity pool `onprem-k8s`, OIDC provider `minikube` | Trusts the cluster's service-account tokens. Its issuer (`https://kubernetes.default.svc.cluster.local`) isn't reachable from Google, so the public keys are uploaded (`onprem-k8s-jwks.json`). The attribute condition accepts only `system:serviceaccount:mini-platform:litellm`. |
| `gcp-stt-poc` | `roles/iam.workloadIdentityUser` on `litellm-stt` for that one subject | Lets the LiteLLM pod impersonate the SA. |
| on-prem host | nftables source rewrite in `ipsec-xfrm.sh` | Without it, traffic into the tunnel leaves as `169.254.0.2`, which GCP can't reply to. |
| mini-platform-deployment | The five models, `litellm` ServiceAccount, projected token, `scripts/gcp-psc-dns.sh` | The client side: token, credential config and DNS. |

## Google APIs

All in the hub project (`mini-cloud-499820`). The `gcp-stt-poc` module enables the first six, with
`disable_on_destroy = false`, so removing the module leaves them on.

| API | Enabled by | Used for |
|-----|------------|----------|
| `speech.googleapis.com` | `gcp-stt-poc` | Speech-to-Text v2 `recognize`, model `chirp_3`, location `eu` |
| `texttospeech.googleapis.com` | `gcp-stt-poc` | Text-to-Speech `text:synthesize`, called on the `eu-texttospeech` endpoint |
| `aiplatform.googleapis.com` | `gcp-stt-poc` | Gemini TTS (`generateContent`, `eu`) and Gemini Live (`BidiGenerateContent`, `europe-west1`) |
| `sts.googleapis.com` | `gcp-stt-poc` | Trades the pod's Kubernetes token for a federated Google token |
| `iamcredentials.googleapis.com` | `gcp-stt-poc` | Trades that for a one-hour token for `litellm-stt` |
| `iam.googleapis.com` | `gcp-stt-poc`, `infra/ci/setup-plan-identity.sh` | The pool, provider and SA; the CI plan job bills the hub, so it needs this to read them |
| `compute.googleapis.com` | already on, **not managed by Terraform** | PSC endpoints, Cloud VPN, Cloud Router |
| `networkconnectivity.googleapis.com` | already on, **not managed by Terraform** | The regional PSC endpoint |
| `orgpolicy.googleapis.com` | already on, **not managed by Terraform** | The `eu` location exception |

The last three predate this work. A fresh hub project needs them enabled by hand before the first
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
   token for `litellm-stt`, and LiteLLM calls the speech API or Vertex AI with it.

The credential config holds no secret, which is why it can live in Git.

## IAM

Everything below was read back from the hub project and the cluster on 2026-11-05.

### Identities

| Identity | Where | Part in the flow |
|----------|-------|------------------|
| `system:serviceaccount:mini-platform:litellm` | Kubernetes service account (created by the postgresql release) | What the LiteLLM pod and its PreSync migration Job run as. Its projected token is the only credential on-prem. |
| Pool `onprem-k8s`, provider `minikube` | Workload identity federation, hub project | Trusts tokens signed by the uploaded cluster keys, issuer `https://kubernetes.default.svc.cluster.local`. Mapping `google.subject = assertion.sub`; condition `assertion.sub == 'system:serviceaccount:mini-platform:litellm'`. No `allowedAudiences`, so the token's audience must be the provider's own name (which the projected volume requests). |
| `litellm-stt@mini-cloud-499820.iam.gserviceaccount.com` | Google service account, hub project | The identity every Google call runs as. **No user-managed keys** (0); it is only ever impersonated. |
| LiteLLM keys | LiteLLM (master key in Secret `litellm-master-key`, virtual keys in its database) | Who may call the models on-prem. Google never sees them; a virtual key can be limited to some models. |

### What `litellm-stt` may do

Its only roles, all on the hub project:

| Role | Permissions | Used by |
|------|-------------|---------|
| `roles/speech.client` | 13: `speech.recognizers.recognize`, `speech.adaptations.execute`, `speech.operations.wait`, and get/list on recognizers, phrase sets, custom classes, operations, locations. No create, update or delete. | `chirp-3` |
| `projects/mini-cloud-499820/roles/litellmVertexCaller` (custom) | `aiplatform.endpoints.predict` only | Gemini chat and TTS (`generateContent`) and Gemini Live (`BidiGenerateContent`); any Gemini model added later needs nothing more. `roles/aiplatform.user` would add creating and deleting Vertex resources. |
| `roles/serviceusage.serviceUsageConsumer` | `serviceusage.services.use` (and read) | LiteLLM sends `x-goog-user-project`, so each call bills the hub as quota project. Text-to-Speech needs nothing more: it has no permission of its own. |

It can't read storage, BigQuery or secrets, can't change IAM, and can't create Vertex endpoints,
recognizers or any other resource.

### Who can act as `litellm-stt`

On the Google side, two checks must both pass:

1. **The provider's attribute condition** rejects any token whose subject isn't
   `system:serviceaccount:mini-platform:litellm` (`rejected by the attribute condition`).
2. **The service account's own policy** has one binding: `roles/iam.workloadIdentityUser` for
   `principal://iam.googleapis.com/projects/311800512343/locations/global/workloadIdentityPools/onprem-k8s/subject/system:serviceaccount:mini-platform:litellm`.

Hub project owners (your user and the `automation` service account) can also impersonate it, as
owners can any service account in the project.

On the Kubernetes side, Google trusts anything holding a valid `litellm` token. Kubernetes has no
permission for "run as this service account": whoever can create pods in `mini-platform` can start
one as `litellm`. Checked with `kubectl auth can-i`:

| Who | Can get a `litellm` token by |
|-----|------------------------------|
| The kubelet | Mounting it into pods that run as `litellm` (LiteLLM, its migration Job) |
| Argo CD application controller | Creating pods (it deploys the namespace) |
| JupyterHub `hub` | Creating pods (it spawns user servers) |
| Spark operator `spark-operator-controller` and `spark-operator-spark` | Creating pods, so a Spark job's driver can start one |
| kagent `kagent-kmcp-controller-manager` | Requesting a token directly (`serviceaccounts/token` in the namespace) |
| Cluster admins | Anything |

So user code that runs through Spark, or a compromised JupyterHub or kagent controller, could call
the speech APIs as `litellm-stt`. That's limited to transcribing, synthesizing and calling Gemini,
billed to the hub. Ways to narrow it, none applied yet:
- Move LiteLLM to its own namespace and update the attribute condition.
- An admission policy that admits `serviceAccountName: litellm` only for the LiteLLM pods.
- Drop `serviceaccounts/token` from kmcp's namespace role.

### Lifetimes and revocation

- **Token lifetimes:** the projected Kubernetes token lives one hour and the kubelet rotates it.
  The federated token and the impersonated access token also last one hour.
- **Revoking:** the two controls stop different steps, so use both.
  - **Removing the `workloadIdentityUser` binding** stops any new `litellm-stt` access token.
    Tokens already issued keep working until they expire, at most an hour.
  - **Disabling the provider** (or the pool) only stops new token exchanges at STS. A federated
    token issued before that still mints `litellm-stt` tokens through the binding until it
    expires. A caller could take a fresh one-hour token just before then, keeping access for up to
    about two hours.
- **Recreated cluster:** new signing keys mean every exchange fails with `invalid_grant` until
  `infra/onprem/refresh-k8s-jwks.sh` uploads them.

### Related controls

- **Location policy:** a project-level `gcp.resourceLocations` policy on the hub inherits the org's
  `europe-west1` list and adds `eu`. Other projects keep the org lock.
- **CI plan job:** the GitHub Actions identity (`infra/ci/setup-plan-identity.sh`) holds
  `roles/viewer`, `roles/iam.securityReviewer` and `roles/serviceusage.serviceUsageConsumer` on the
  hub. With those it plans these resources, IAM policies and the custom role included, but can't
  change them.
- **Applies:** an owner runs them today. The roles below are enough, without owner.

### Deployer roles (least privilege)

The roles needed to build the speech services from scratch in a single existing project. That
means the identity pool, `litellm-stt`, the APIs and, for the private path, the VPN and PSC
endpoints. No `owner` or `editor`. Each role was checked with `gcloud iam roles describe` against
the resources Terraform creates.

**Always needed**, on the project:

| Role | Creates |
|------|---------|
| `roles/serviceusage.serviceUsageAdmin` | Turns on `speech`, `texttospeech`, `aiplatform`, `sts`, `iamcredentials`, `iam` (plus `compute` and `networkconnectivity` for the private path). Also lets Terraform bill the project as quota project. |
| `roles/iam.serviceAccountAdmin` | `litellm-stt` and its single `workloadIdentityUser` binding |
| `roles/iam.workloadIdentityPoolAdmin` | Pool `onprem-k8s` and provider `minikube`; later JWKS uploads (`refresh-k8s-jwks.sh`) |
| `roles/iam.roleAdmin` | The custom role `litellmVertexCaller` |
| `roles/resourcemanager.projectIamAdmin`, **with the condition below** | The three project-level grants to `litellm-stt`, and nothing else |

```
api.getAttribute('iam.googleapis.com/modifiedGrantsByRole', [])
  .hasOnly(['roles/speech.client',
            'roles/serviceusage.serviceUsageConsumer',
            'projects/PROJECT_ID/roles/litellmVertexCaller'])
```

Without the condition, `projectIamAdmin` could grant any role to anyone. Leaving out
`roles/iam.roleAdmin` means giving `litellm-stt` the predefined `roles/aiplatform.user` instead of
the custom role, which also lets it create and delete Vertex resources.

**Private path only** (VPN and PSC endpoints):

| Role | Creates |
|------|---------|
| `roles/compute.networkAdmin` | VPC and subnets, HA VPN gateway, peer gateway, tunnel, Cloud Router and BGP peer, the `all-apis` PSC endpoint (with its Service Directory namespace), the regional endpoint for `aiplatform.eu.rep.googleapis.com` |

Without the VPN, LiteLLM calls the same APIs over the internet with the same keyless login, and
this role isn't needed. `roles/compute.securityAdmin` isn't needed either: PSC endpoints need no
firewall rules.

**Terraform state.** If the state lives in a bucket of the project, someone creates the bucket
once (`roles/storage.admin`). After that the deployer needs only `roles/storage.objectUser` on that
bucket. Local state needs no role.

**Location exception.** Chirp 3 and the Gemini 3.8 TTS models run only in `us`, `eu` or `global`.
If an org policy restricts locations, as this org's `europe-west1` lock does, the project needs a
`gcp.resourceLocations` exception adding `eu`. The `gcp-stt-poc` module manages it
(`google_org_policy_policy.allow_eu`) unless told otherwise. Writing it, and even refreshing it,
needs org-policy permissions:
- **Terraform manages it (default, `stt_manage_location_policy = true`):** the deployer also needs
  `roles/orgpolicy.policyAdmin`. It can only be granted at org or folder level, and it covers every
  org policy.
- **An org admin owns it (least privilege):** set `stt_manage_location_policy = false`. The
  exception is then outside Terraform's state, so the deployer needs no org-policy permission, not
  even read access. The org admin creates it once (or skips it if no location policy applies).

To hand an existing exception over, take it out of state first. Run this in
`infra/stacks/gcp-poc` with the credentials you apply with: the state is shared, in the GCS bucket.
The address ends in `allow_eu` before the first apply with the `moved` block and in `allow_eu[0]`
after it, so look it up:

```bash
terraform state list | grep allow_eu
terraform state rm '<the address printed above>'
```

Then set `stt_manage_location_policy = false`. Setting the variable without `state rm` makes the next
apply **delete** the exception.

**Not needed:**
- `owner` or `editor`
- any Speech or Text-to-Speech admin role (Text-to-Speech has no permission of its own)
- `aiplatform.admin`
- `iam.serviceAccountTokenCreator`: on-prem logs in through the pool, not through the deployer

In this repo the speech services sit in the hub project (`mini-cloud-499820`), and the same roles
cover them there. The hub's other resources (firewall rules, Shared VPC, the lakehouse spoke) need
more, outside this doc. To prove the list, run a from-scratch apply into a fresh project with a
service account holding exactly these roles: a 403 names any missing permission.

## Bring-up

```bash
# 1. GCP (from infra/stacks/gcp-poc)
terraform plan && terraform apply

# 2. On-prem host: rebuild ipsec0 with the source rewrite, then restart FRR
sudo apt-get install -y nftables              # if not already installed
sudo install -m 0755 infra/onprem/strongswan/ipsec-xfrm.sh /usr/local/sbin/mini-cloud-ipsec-xfrm.sh
sudo install -m 0644 infra/onprem/systemd/mini-cloud-vpn.service /etc/systemd/system/
sudo systemctl daemon-reload && sudo systemctl restart mini-cloud-vpn frr

# 3. Cluster DNS (from mini-platform-deployment): pin the API names to the PSC endpoints
#    (terraform outputs psc_googleapis_ip and psc_rep_ips)
scripts/gcp-psc-dns.sh 10.48.64.2 10.48.65.2
```

Then merge the mini-platform-deployment change; Argo CD rolls LiteLLM with the new models.

## Verify

```bash
ip route get 10.48.64.2                       # via 169.254.0.1 dev ipsec0
ip route get 10.48.65.2                       # same, learned from the subnet advertisement
sudo nft list table ip mini_cloud_vpn         # snat to the LAN address

KEY=$(kubectl -n mini-platform get secret litellm-master-key -o jsonpath='{.data.PROXY_MASTER_KEY}' | base64 -d)
kubectl -n mini-platform port-forward svc/litellm 4000:4000 &
curl -s localhost:4000/v1/audio/transcriptions -H "Authorization: Bearer $KEY" \
  -F model=chirp-3 -F file=@sample.wav -F language=fr-FR

curl -s localhost:4000/v1/audio/speech -H "Authorization: Bearer $KEY" -H 'Content-Type: application/json' \
  -d '{"model":"tts-chirp-3-hd","input":"Bonjour depuis le cloud.","voice":"fr-FR-Chirp3-HD-Aoede","response_format":"mp3"}' \
  -o bonjour.mp3

curl -s localhost:4000/v1/audio/speech -H "Authorization: Bearer $KEY" -H 'Content-Type: application/json' \
  -d '{"model":"gemini-3.8-flash-tts","input":"The tunnel to Belgium works.","voice":"Kore"}' \
  -o gemini.wav                               # 16-bit mono 24 kHz WAV

curl -s localhost:4000/v1/chat/completions -H "Authorization: Bearer $KEY" -H 'Content-Type: application/json' \
  -d '{"model":"gemini-3.8-flash","messages":[{"role":"user","content":"What is the capital of Belgium?"}]}'
```

Feeding the audio back to `chirp-3` is a quick round trip check. `gemini-live` needs a websocket
client: connect to `ws://localhost:4000/v1/realtime?model=gemini-live` with the key as a bearer
token, stream 16-bit PCM in `input_audio_buffer.append` events, and read the
`conversation.item.input_audio_transcription.*` events.

`sudo tcpdump -ni ipsec0 'host 10.48.64.2 or host 10.48.65.2'` shows the requests leaving through
the tunnel.

## Limits and upkeep

- **One minute, 10 MB per request.** LiteLLM uses the synchronous `recognize` method. Longer audio
  has to be split into clips; Chirp 3's `BatchRecognize` is not wired up.
- **Locations.** Chirp 3, the Gemini 3.8 TTS models and the Gemini chat models run only in
  `global`, `us` or `eu` (none in `europe-west1`); `eu`
  keeps the data in Europe, and the hub's location exception allows only that. Another location
  needs the exception widened, plus DNS entries (and, for Vertex `rep` names, another regional
  endpoint).
- **Gemini Live.** The websocket goes through the ingress at `litellm.test` too, but sessions are
  long-lived: proxy timeouts apply. Every turn returns the input transcript and a spoken reply (the
  model answers; LiteLLM doesn't offer a transcribe-only mode). Tested over two turns in
  `europe-west1`; Google's GA model has open reports of silent audio in production.
- **Recreated cluster.** New signing keys: run `infra/onprem/refresh-k8s-jwks.sh` and commit the
  JSON, or every token exchange fails with `invalid_grant`.
- **Voices.** `tts-chirp-3-hd` needs a Google voice name (`<lang>-Chirp3-HD-<voice>`); the OpenAI
  names (`alloy`, `nova` …) fall back to older WaveNet voices. The Gemini TTS models take Gemini
  voice names (`Kore`, `Charon`, `Aoede` …) and always return 16-bit 24 kHz WAV, whatever
  `response_format` asks for. Through LiteLLM's `/v1/audio/speech`
  they read the whole input aloud: a lead-in like "Say cheerfully:" is spoken, not obeyed.
- **Gemini chat models.** Gemini 4 has one model on Vertex AI, `gemini-4-argon` (no Flash or Pro
  names); its `-cyber-permissive` variant is left out. Gemini 3.1 Pro is preview and served only in `global`, which has no EU
  data residency, so it isn't offered. Google retires Gemini versions often: LiteLLM's cost map
  lists `gemini-3.5-flash` until 19 May 2027 and `gemini-3.5-flash-lite` until 21 July 2027. A
  newer model is one more entry in `litellm-values.yaml` (same location and credentials), as long
  as Google serves it in `eu`.
- **Tunnel down = no speech.** Cluster DNS sends the API names only to the PSC IPs. Run
  `scripts/gcp-psc-dns.sh --remove` to fall back to the public endpoints. The keyless login still
  works that way, since the APIs are public, only the private path is lost.
- **Cost.** See [Cost](#cost).

## Cost

Billed to the hub project. List prices in USD; check the
[Speech-to-Text](https://cloud.google.com/speech-to-text/pricing),
[Gemini](https://aistudio.google.com/docs/pricing) and
[VPC](https://cloud.google.com/vpc/network-pricing#psc-forwarding-rules) pricing pages before budgeting.
Gemini audio is metered at 25 tokens per second, so one minute of audio is 1,500 tokens.

| Item | Price | Monthly at test volume |
|------|-------|------------------------|
| PSC endpoint for Google APIs (`all-apis`) | $0.01 per hour | ≈ $7.30 |
| Its data processing | none: a global Google APIs endpoint has no data charge | $0 |
| Regional PSC endpoint (`aiplatform.eu.rep`) | $0.01 per hour, plus per-GB data processing | ≈ $7.30; TTS text and audio are small |
| Chirp 3 transcription | $0.016 per minute (standard v2 recognition, first 500k min/month) | 2-second clip ≈ $0.0005; 1,000 min ≈ $16 |
| Chirp 3 HD speech | $30 per 1M characters, first 1M characters a month free | ≈ $0 within the free tier; a 1,000-word page ≈ $0.18 beyond it |
| Gemini 3.8 Flash TTS | $0.50 / 1M text-in tokens, $9.00 / 1M audio-out tokens, **doubling to $1.00 / $18.00 on 1 Jan 2027** | ≈ $0.0135 per minute of speech ($0.027 from 2027) |
| Gemini 3.8 Flash-Lite TTS | $0.50 / 1M text in, $6.00 / 1M audio out, **doubling to $1.00 / $12.00 on 1 Jan 2027** | ≈ $0.009 per minute of speech ($0.018 from 2027) |
| Gemini Live 2.5 Flash native audio | $3.00 / 1M audio-in tokens, $12.00 / 1M audio-out; text $0.50 in, $2.00 out | transcribing 1 minute ≈ $0.0045 in, plus any spoken reply |
| Gemini 4 Argon (chat) | $2.00 / 1M input tokens, $10.00 / 1M output | a short question ≈ $0.0002 |
| Gemini 3.8 Flash (chat) | $0.75 / 1M input tokens, $3.75 / 1M output | a short question ≈ $0.0004 |
| Gemini 3.5 Flash (chat) | $1.50 / 1M input tokens, $9.00 / 1M output (thinking tokens bill as output) | a short question ≈ $0.0013 |
| Gemini 3.5 Flash-Lite (chat) | $0.30 / 1M input tokens, $2.50 / 1M output | a short question ≈ $0.00002 |
| Cloud VPN tunnel (already there, doc 08) | $0.05 per hour × 1 tunnel | ≈ $36.50 |
| Replies back over the tunnel | internet egress rates (the peer is outside Google) | ≈ $0 at test volume; audio replies are larger than text |
| STS, IAM Credentials, pool, SA, custom role, location policy, Cloud Router | free | $0 |

So the speech services add about **$14.60 a month fixed** (two private endpoints) plus the per-use
charges; the fixed part doesn't grow with traffic.

Unconfirmed figures:
- Google lists $0.016/min for standard v2 recognition. That Chirp 3 has no premium comes from
  third-party sources, as does the Chirp 3 HD voice rate.
- The Gemini rates are the Gemini API's Standard tier. Vertex AI's page didn't render when this was
  written. The regional endpoint's per-GB rate isn't confirmed either.

LiteLLM loads its cost map from upstream at startup; it lists the Gemini 3.8 TTS models ($9 and
$6 per 1M audio tokens) and Gemini Live ($3 in, $12 out), matching the rates above. The Gemini
chat rates are taken from that map alone, not from Google's page. LiteLLM records spend for the
chat models (a one-sentence answer cost $0.00002 to $0.0013) and for Gemini Live (the two-turn
test: $0.00036). The Gemini TTS models show **$0** in
`litellm_spend_metric_total`: LiteLLM 1.98's speech bridge doesn't pass Google's token counts on, so
their cost appears only in Google billing and Cloud Monitoring.

### Watching usage

- **LiteLLM (Prometheus/Grafana in mini-platform):** `litellm_proxy_total_requests_metric_total`
  by `requested_model` and `status_code`, `litellm_llm_api_latency_metric`,
  `litellm_spend_metric_total`. Traces go to Tempo and Langfuse.
- **Google (Cloud Monitoring, free):** `serviceruntime.googleapis.com/api/request_count` for
  `speech.googleapis.com` (method `Speech.Recognize`), `texttospeech.googleapis.com` and
  `aiplatform.googleapis.com`, by response code.
- No dashboard, alert or budget exists yet for any of the models.
