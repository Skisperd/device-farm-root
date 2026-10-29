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

## — MCP server (Appium ↔ Claude) ————————————————————————————————
SUITE   ?= example/android_smoke.robot
RESULTS ?= robot/results

mcp-install: ## Install MCP server Python dependencies
	@pip install -r mcp/requirements.txt

mcp-start: ## Start the MCP server (stdio — used by Claude Code / Desktop)
	@PYTHONPATH=. APPIUM_URL=$${APPIUM_URL:-http://localhost:4723} python -m mcp.server

## — Robot Framework tests ————————————————————————————————————————
robot-test: ## Run a Robot suite (SUITE=path, vars: APP_PACKAGE APP_ACTIVITY APP_PATH)
	@mkdir -p $(RESULTS)/screenshots
	@python -m robot \
	  --outputdir $(RESULTS) \
	  -v APPIUM_URL:$${APPIUM_URL:-http://localhost:4723} \
	  $(if $(APP_PATH),-v APP_PATH:$(APP_PATH),) \
	  $(if $(APP_PACKAGE),-v APP_PACKAGE:$(APP_PACKAGE),) \
	  $(if $(APP_ACTIVITY),-v APP_ACTIVITY:$(APP_ACTIVITY),) \
	  robot/tests/$(SUITE)
	@echo "Report: $(RESULTS)/report.html"

robot-list: ## List available Robot suites and test cases
	@find robot/tests -name "*.robot" | sort | while read f; do \
	  echo "\n\033[36m$$f\033[0m"; \
	  grep -E '^[A-Z][^*]' "$$f" 2>/dev/null | sed 's/^/  /'; \
	done

## — Shortcuts ————————————————————————————————————————————————————
up: farm-up emulators-up ## Start hub + emulators
down: emulators-down farm-down ## Stop emulators + hub

## — Help —————————————————————————————————————————————————————————
help: ## Show this help
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage:\n  make \033[36m<target>\033[0m\n\nTargets:\n"} \
	  /^[a-zA-Z_-]+:.*?##/ { printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2 }' $(MAKEFILE_LIST)

.PHONY: farm-up farm-down farm-status farm-logs farm-reconnect \
        emulators-up emulators-down emulators-status emulators-list emulators-reset emulator-view \
        mcp-install mcp-start \
        robot-test robot-list \
        up down help
