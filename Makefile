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
