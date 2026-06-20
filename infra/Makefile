# Terraform workflow across the three landing-zone stacks + policy.
# Usage:
#   make fmt              # format all .tf
#   make validate         # init -backend=false + validate every stack/module
#   make plan STACK=aws   # plan a single stack (aws|azure|gcp)
#   make plan-all         # plan every stack
# CI runs fmt-check + validate (no creds needed); plan runs where creds are present.

STACKS      := aws azure gcp
STACK_DIRS  := $(addprefix stacks/,$(STACKS))
TF          := terraform

.PHONY: fmt fmt-check validate plan plan-all $(addprefix plan-,$(STACKS)) clean diagram apply-poc

fmt:
	$(TF) fmt -recursive .

fmt-check:
	$(TF) fmt -recursive -check -diff .

# Backend-less init + validate works offline (no remote state, no creds).
validate:
	@set -e; for d in $(STACK_DIRS) stacks/gcp-poc stacks/aws-poc stacks/azure-poc policy/aws policy/gcp; do \
		echo "==> validate $$d"; \
		$(TF) -chdir=$$d init -backend=false -input=false >/dev/null; \
		$(TF) -chdir=$$d validate; \
	done

# Single stack: make plan STACK=aws
plan:
	@test -n "$(STACK)" || { echo "set STACK=aws|azure|gcp"; exit 1; }
	$(TF) -chdir=stacks/$(STACK) init -input=false
	$(TF) -chdir=stacks/$(STACK) plan -input=false

plan-all: $(addprefix plan-,$(STACKS))

plan-%:
	$(TF) -chdir=stacks/$* init -input=false
	$(TF) -chdir=stacks/$* plan -input=false

# Live diagram from the GCP PoC state (Inframap + Graphviz). Regenerate after any
# apply so the SVG follows the real resources. STATE overrides the source state.
STATE ?= stacks/gcp-poc/terraform.tfstate
diagram:
	@command -v dot >/dev/null || { echo "install graphviz (dot)"; exit 1; }
	@test -f "$(STATE)" || { echo "no state at $(STATE) — apply first"; exit 1; }
	./diagram/gen-live-diagram.sh "$(STATE)" ../docs/diagrams/live-gcp-poc.svg

# Post-apply hook: apply the GCP PoC, then regenerate the live diagram so the
# committed SVG always tracks the deployed resources.
apply-poc:
	$(TF) -chdir=stacks/gcp-poc apply
	$(MAKE) diagram

clean:
	find . -type d -name '.terraform' -prune -exec rm -rf {} +
	find . -type f -name '.terraform.lock.hcl' -delete
