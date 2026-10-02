.DEFAULT_GOAL := help

COMPOSE = docker compose -f infra/docker-compose.yml --env-file .env
N ?= 2

## — Farm (Docker hub) ——————————————————————————————————————————————
farm-up: ## Start Appium hub + device-farm (dashboard at http://localhost:4723/device-farm)
	@$(COMPOSE) up -d --build
	@echo "Dashboard: http://localhost:4723/device-farm"

farm-down: ## Stop the hub
	@$(COMPOSE) --profile emulator --profile runner down

farm-status: ## Show registered devices and queue
	@scripts/farm-status.sh

farm-logs: ## Follow hub logs
	@docker logs appium-hub -f

farm-reconnect: ## Recreate hub (apply .env changes)
	@$(COMPOSE) up -d --force-recreate appium-hub

## — Emulators (native macOS) ———————————————————————————————————————
emulators-up: ## Start N headless Android emulators connected to the hub (N=2)
	@scripts/emulators.sh up $(N)

emulators-down: ## Stop project emulators
	@scripts/emulators.sh down

emulators-status: ## List running emulators
	@scripts/emulators.sh status

emulators-list: ## List device catalog
	@scripts/emulators.sh list

emulators-reset: ## Delete AVDs (recreated on next emulators-up)
	@scripts/emulators.sh reset

emulator-view: ## Mirror emulator screen with scrcpy (I=1)
	@scripts/emulators.sh view $(or $(I),1)

## — Shortcuts ————————————————————————————————————————————————————
up: farm-up emulators-up ## Start hub + emulators
down: emulators-down farm-down ## Stop emulators + hub

## — Help —————————————————————————————————————————————————————————
help: ## Show this help
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage:\n  make \033[36m<target>\033[0m\n\nTargets:\n"} \
	  /^[a-zA-Z_-]+:.*?##/ { printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2 }' $(MAKEFILE_LIST)

.PHONY: farm-up farm-down farm-status farm-logs farm-reconnect \
        emulators-up emulators-down emulators-status emulators-list emulators-reset emulator-view \
        up down help
