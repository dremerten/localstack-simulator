.PHONY: help up down clean logs health smoke

help: ## show available targets
	@printf "Targets:\n"
	@while IFS= read -r line; do \
		case "$$line" in \
			[a-zA-Z0-9_-]*:*"##"*) \
				target=$${line%%:*}; \
				desc=$${line##*## }; \
				printf "  %-12s %s\n" "$$target" "$$desc"; \
				;; \
		esac; \
	done < $(firstword $(MAKEFILE_LIST))

up: ## build and start
	docker compose up -d --build

down: ## stop
	docker compose down

clean: ## stop and remove volumes
	docker compose down -v

logs: ## tail logs
	docker compose logs -f --tail=200

health: ## run host healthcheck
	./scripts/healthcheck.sh

smoke: ## run iac-sandbox awscli smoke test
	./scripts/smoke.sh
