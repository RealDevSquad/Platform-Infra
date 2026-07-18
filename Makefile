# Convenience entrypoints — run from the repo root, no need to know the layout.
#   make up                          # all profiles
#   make up PROFILES=todo            # subset
#   make ps / logs S=todo-backend / down / down-data

PROFILES ?= todo,skilltree,tinysite,discord
COMPOSE   = cd docker && COMPOSE_PROFILES=$(PROFILES) docker compose

.PHONY: up down down-data ps logs config

up:
	$(COMPOSE) up -d

down:
	$(COMPOSE) down

down-data:
	$(COMPOSE) down -v

ps:
	$(COMPOSE) ps

logs:
	$(COMPOSE) logs -f $(S)

config:
	$(COMPOSE) config --quiet && echo "compose config: VALID"

# ---- OpenTofu remote state (docs/remote-state.md) ----
# make state-bootstrap            # once per ACCOUNT (with that account's creds)
# make init MODULE=tofu           # per module+machine: discover bucket, tofu init
STATE_PARAM  = /rds/tofu/state-bucket
STATE_PREFIX = rds-tofu-state-
AWS_REGION  ?= ap-south-1

.PHONY: state-bootstrap init

state-bootstrap:
	cd tofu-state-bootstrap && tofu init && tofu apply

init:
	@test -n "$(MODULE)" || { echo "usage: make init MODULE=tofu|tofu-prod-import"; exit 2; }
	@test -f "$(MODULE)/backend.tf" || { echo "$(MODULE) has not adopted remote state — adopt first:"; echo "  cp $(MODULE)/backend.tf.example $(MODULE)/backend.tf"; exit 2; }
	@BUCKET=$$(aws ssm get-parameter --name $(STATE_PARAM) --query Parameter.Value --output text 2>/dev/null); \
	if [ -z "$$BUCKET" ] || [ "$$BUCKET" = "None" ]; then \
	  BUCKET=$$(aws s3api list-buckets --query "Buckets[?starts_with(Name, '$(STATE_PREFIX)')].Name | [0]" --output text 2>/dev/null); \
	fi; \
	if [ -z "$$BUCKET" ] || [ "$$BUCKET" = "None" ]; then \
	  echo "no state bucket discoverable in this account (SSM $(STATE_PARAM), prefix $(STATE_PREFIX))"; \
	  echo "run 'make state-bootstrap' once with this account's credentials"; exit 2; \
	fi; \
	echo "state bucket: $$BUCKET  (key: $(MODULE)/terraform.tfstate)"; \
	cd $(MODULE) && tofu init \
	  -backend-config="bucket=$$BUCKET" \
	  -backend-config="key=$(MODULE)/terraform.tfstate" \
	  -backend-config="region=$(AWS_REGION)"
