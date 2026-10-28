-include .env

COMPOSE := docker compose
DB_PORT ?= 5432
LOCAL_DATABASE_URL := $(subst @db:5432,@localhost:$(DB_PORT),$(DATABASE_URL))
s ?=

.DEFAULT_GOAL := help
.PHONY: help env build up down restart logs ps migrate migration seed psql test lint format \
	report-local report-now report-ls report-logs \
	llm-hello parse dev-parser parser-logs infra-init infra-fmt infra-plan infra-output infra-env \
	dev-backend dev-frontend install clean deploy deploy-backend deploy-frontend destroy-backend destroy-frontend add-domain remove-domain add-api-domain destroy-api infra-lint

help: ## Show this help
	@grep -hE '^[a-zA-Z_-]+:.*?## ' $(firstword $(MAKEFILE_LIST)) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-16s\033[0m %s\n", $$1, $$2}'

env: ## Create .env from .env.example if missing
	@test -f .env || (cp .env.example .env && echo "Created .env")

build: env ## Build all images
	$(COMPOSE) build

up: env ## Build and start the whole stack
	$(COMPOSE) up -d --build
	@echo "App:      http://localhost:3000"
	@echo "API docs: http://localhost:8000/api/docs"

down: ## Stop the stack
	$(COMPOSE) down

restart: down up ## Restart the stack

logs: ## Follow logs (optionally: make logs s=backend)
	$(COMPOSE) logs -f $(s)

ps: ## Show running services
	$(COMPOSE) ps

migrate: ## Apply database migrations
	$(COMPOSE) exec backend alembic upgrade head

migration: ## Generate a migration: make migration m="add something" (db must be up)
	@test -n "$(m)" || (echo 'Usage: make migration m="message"' && exit 1)
	cd backend && DATABASE_URL=$(LOCAL_DATABASE_URL) uv run alembic revision --autogenerate -m "$(m)"

seed: ## Insert sample participants and meetings
	$(COMPOSE) exec backend python -m app.seed

report-local: ## Print a weekly report from the local database: make report-local WEEK=2026-W40
	$(COMPOSE) exec backend python -m app.reports.weekly $(WEEK)

psql: ## Open psql in the db container
	$(COMPOSE) exec db psql -U $(POSTGRES_USER) -d $(POSTGRES_DB)

test: ## Run backend tests (against the <db>_test database)
	$(COMPOSE) exec backend pytest -v

lint: ## Lint backend and frontend
	cd backend && uv run ruff check . && uv run ruff format --check .
	cd frontend && npm run lint && npx prettier --check .

format: ## Format backend and frontend
	cd backend && uv run ruff check --fix . && uv run ruff format .
	cd frontend && npm run format

install: ## Install local dev dependencies (uv + npm)
	cd backend && uv sync
	cd frontend && npm install

dev-backend: env ## Run backend locally with reload (db runs in Docker)
	$(COMPOSE) up -d db
	cd backend && DATABASE_URL=$(LOCAL_DATABASE_URL) uv run alembic upgrade head
	cd backend && DATABASE_URL=$(LOCAL_DATABASE_URL) uv run uvicorn app.main:app --reload --port 8000

dev-frontend: ## Run Vite dev server on http://localhost:5173 (proxies /api to :8000)
	cd frontend && npm run dev

clean: ## Stop the stack and delete the database volume
	$(COMPOSE) down -v

# AWS credentials and settings come from .env; export them only to the recipes below.
AWS_ENV := AWS_ACCESS_KEY_ID="$(AWS_ACCESS_KEY_ID)" AWS_SECRET_ACCESS_KEY="$(AWS_SECRET_ACCESS_KEY)" \
	AWS_SESSION_TOKEN="$(AWS_SESSION_TOKEN)" AWS_REGION="$(AWS_REGION)" \
	PROJECT_NAME="$(or $(PROJECT_NAME),$(APP_NAME))" CORS_ORIGINS_AWS="$(CORS_ORIGINS_AWS)" \
	LAMBDA_MEMORY="$(LAMBDA_MEMORY)" DOMAIN_NAME="$(DOMAIN_NAME)" API_DOMAIN_NAME="$(API_DOMAIN_NAME)" HOSTED_ZONE_ID="$(HOSTED_ZONE_ID)" \
	WEEK="$(WEEK)" \
	PARSER_MODEL="$(PARSER_MODEL)" BEDROCK_REGION="$(BEDROCK_REGION)" \
	BEDROCK_API="$(BEDROCK_API)" PARSER_EFFORT="$(PARSER_EFFORT)" PARSER_FAKE="$(PARSER_FAKE)"

deploy: deploy-backend deploy-frontend ## Deploy the app to AWS (the Terraform part is applied by HCP Terraform)

deploy-backend: env ## Deploy backend (Lambda) + database (Aurora Serverless) to AWS, see infra/
	@$(AWS_ENV) ./infra/deploy-backend.sh

deploy-frontend: env ## Deploy frontend to S3 + CloudFront, wired to the Lambda URL (after deploy-backend)
	@$(AWS_ENV) ./infra/deploy-frontend.sh

add-domain: env ## Attach DOMAIN_NAME from .env to the deployed frontend
	@$(AWS_ENV) ./infra/add-domain.sh

remove-domain: env ## Detach the custom domain and delete its certificate
	@$(AWS_ENV) ./infra/remove-domain.sh

add-api-domain: env ## Put the backend on API_DOMAIN_NAME from .env (CloudFront + certificate)
	@$(AWS_ENV) ./infra/add-api-domain.sh

destroy-api: env ## Delete the API domain (its CloudFront distribution and certificate)
	@$(AWS_ENV) ./infra/destroy-api.sh

destroy-backend: env ## Delete the AWS backend stacks (keeps a final DB snapshot)
	@$(AWS_ENV) ./infra/destroy-backend.sh

destroy-frontend: env ## Delete the S3 bucket, CloudFront distribution and domain certificate
	@$(AWS_ENV) ./infra/destroy-frontend.sh

infra-lint: ## Lint the CloudFormation templates and the Terraform files
	uvx cfn-lint infra/*.yaml
	terraform -chdir=infra fmt -check -recursive
	terraform -chdir=infra validate

# ---------------------------------------------------------------- Weekly report (infra/reports.tf)
report-now: env ## Build and email a report now: make report-now WEEK=2026-W40 (default: last week)
	@$(AWS_ENV) ./infra/report-now.sh

report-ls: env ## List the reports in S3
	@$(AWS_ENV) bash -c 'source infra/common.sh && aws s3 ls "s3://$$(tf_output reports_bucket)/reports/" --recursive'

report-logs: env ## Show which event started the builder and the mailer (last 24 h)
	@$(AWS_ENV) ./infra/report-logs.sh

# ---------------------------------------------------------------- Agenda parser (app/ai, infra/ai.tf)
# These run on your laptop with the AWS credentials from .env; Bedrock is called in BEDROCK_REGION.
# infra/common.sh drops an empty AWS_SESSION_TOKEN, which would otherwise break the credentials.
llm-hello: env ## First call to Claude on Bedrock: prints the answer, stop_reason and usage
	@$(AWS_ENV) bash -c 'source infra/common.sh && cd backend && uv run python -m app.ai.hello'

parse: env ## Parse an agenda from the laptop: make parse TEXT="..." [TODAY=2026-10-27] [PARSER_MODEL=...]
	@test -n "$(TEXT)" || (echo 'Usage: make parse TEXT="..."' && exit 1)
	@$(AWS_ENV) TEXT="$$TEXT" TODAY="$(TODAY)" bash -c 'source infra/common.sh && cd backend && uv run python -m app.ai.agenda'

dev-parser: env ## Run the parser on :8001 (Vite proxies /parse to it); PARSER_FAKE=true needs no Bedrock
	@$(AWS_ENV) COGNITO_USER_POOL_ID="$(COGNITO_USER_POOL_ID)" COGNITO_CLIENT_ID="$(COGNITO_CLIENT_ID)" \
		PARSER_FAKE="$(or $(PARSER_FAKE),false)" \
		bash -c 'source infra/common.sh && cd backend && uv run uvicorn app.ai.agenda_lambda:app --reload --port 8001'



parser-logs: env ## The parser's log lines of the last 24 h (model, tokens, latency, cost)
	@$(AWS_ENV) ./infra/parser-logs.sh

# ---------------------------------------------------------------- Terraform (infra/*.tf)
# Cognito, the weekly report and the agenda parser are Terraform, with the state in HCP Terraform
# (workspace spry-dev). There is no apply here on purpose: HCP Terraform applies after a merge to
# main. A plan from the laptop runs in HCP Terraform too (speculative, it changes nothing).
infra-init: ## Connect infra/ to HCP Terraform (after terraform login)
	terraform -chdir=infra init -input=false

infra-fmt: ## Format the Terraform files
	terraform -chdir=infra fmt -recursive

infra-plan: ## Plan the Terraform part in HCP Terraform (changes nothing)
	terraform -chdir=infra plan

infra-output: ## Show the Terraform outputs (Cognito ids, parser URL, report queue, ...)
	terraform -chdir=infra output

infra-env: env ## Write the Cognito settings from the Terraform outputs to .env (for local runs)
	@./infra/write-env.sh
