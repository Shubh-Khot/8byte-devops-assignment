# Shortcuts for the things I run constantly. Everything here is a thin wrapper
# over the real command, so nothing is hidden - `make -n <target>` shows you
# exactly what will run.

COMPOSE      := docker compose
COMPOSE_ALL  := docker compose -f docker-compose.yml -f docker-compose.monitoring.yml
PY_IMAGE     := python:3.12-slim
TF_ENV       ?= staging

.DEFAULT_GOAL := help

.PHONY: help
help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
		| awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-22s\033[0m %s\n", $$1, $$2}'

# --- local development ------------------------------------------------------

.PHONY: up
up: ## Start the app and Postgres
	$(COMPOSE) up -d --build
	@echo "API: http://localhost:8000/docs"

.PHONY: down
down: ## Stop everything, keep the data
	$(COMPOSE_ALL) down

.PHONY: clean
clean: ## Stop everything and delete volumes
	$(COMPOSE_ALL) down -v

.PHONY: logs
logs: ## Tail application logs
	$(COMPOSE) logs -f api

# --- observability ----------------------------------------------------------

.PHONY: monitoring
monitoring: ## Start the app plus Prometheus, Loki, Grafana, exporters
	$(COMPOSE_ALL) up -d --build
	@echo ""
	@echo "  Grafana        http://localhost:3000   (admin/admin)"
	@echo "  Prometheus     http://localhost:9090"
	@echo "  Alertmanager   http://localhost:9093"
	@echo "  API            http://localhost:8000/docs"

.PHONY: load
load: ## Generate 60s of demo traffic
	./scripts/generate-load.sh 60

.PHONY: load-errors
load-errors: ## Generate traffic including 5xx, to trip the error-rate alert
	./scripts/generate-load.sh 120 errors

# --- quality gates ----------------------------------------------------------
#
# These run in a container rather than against the host interpreter so they
# behave identically here and in CI, whatever Python happens to be installed.

.PHONY: test
test: ## Run the full test suite against the compose Postgres
	@$(COMPOSE) up -d db >/dev/null
	docker run --rm --network $$(docker network ls --format '{{.Name}}' | grep -m1 $$(basename $$PWD)) \
		-v "$$PWD/app:/app" -w /app \
		-e DB_HOST=db -e DB_USER=tasks -e DB_PASSWORD=localdev -e DB_NAME=tasksdb \
		$(PY_IMAGE) sh -c "pip install --quiet -r requirements-dev.txt && python -m pytest tests -v"

.PHONY: test-unit
test-unit: ## Run only the tests that need no database
	docker run --rm -v "$$PWD/app:/app" -w /app $(PY_IMAGE) \
		sh -c "pip install --quiet -r requirements-dev.txt && python -m pytest tests -m 'not integration' -v"

.PHONY: lint
lint: ## Lint and format-check the application
	docker run --rm -v "$$PWD:/w" -w /w $(PY_IMAGE) \
		sh -c "pip install --quiet ruff==0.8.4 && ruff check app/ && ruff format --check app/"

.PHONY: fmt
fmt: ## Auto-fix lint and formatting
	docker run --rm -v "$$PWD:/w" -w /w $(PY_IMAGE) \
		sh -c "pip install --quiet ruff==0.8.4 && ruff check --fix app/ && ruff format app/"
	terraform fmt -recursive terraform/

.PHONY: audit
audit: ## Scan dependencies and the image for known vulnerabilities
	docker run --rm -v "$$PWD:/w" -w /w $(PY_IMAGE) \
		sh -c "pip install --quiet pip-audit==2.7.3 && pip-audit -r app/requirements.txt --desc"
	docker build -q -t task-api:audit . >/dev/null
	docker run --rm -v /var/run/docker.sock:/var/run/docker.sock \
		aquasec/trivy:latest image --severity HIGH,CRITICAL --ignore-unfixed task-api:audit

.PHONY: smoke
smoke: ## Run the smoke test against the local stack
	./scripts/smoke-test.sh http://localhost:8000

# --- infrastructure ---------------------------------------------------------

.PHONY: tf-validate
tf-validate: ## fmt-check and validate every Terraform root and module
	terraform fmt -check -recursive terraform/
	@for d in terraform/bootstrap terraform/envs/* terraform/modules/*; do \
		echo "==> $$d"; \
		terraform -chdir=$$d init -backend=false -input=false >/dev/null; \
		terraform -chdir=$$d validate || exit 1; \
	done

.PHONY: tf-plan
tf-plan: ## Plan an environment: make tf-plan TF_ENV=prod
	terraform -chdir=terraform/envs/$(TF_ENV) plan

.PHONY: tf-apply
tf-apply: ## Apply an environment: make tf-apply TF_ENV=staging
	terraform -chdir=terraform/envs/$(TF_ENV) apply

.PHONY: tf-destroy
tf-destroy: ## Tear an environment down: make tf-destroy TF_ENV=staging
	./scripts/teardown.sh $(TF_ENV)
