# JenkinsForge — local pipeline reproduction
# Every target mirrors a Jenkins stage so developers can verify locally.

APP_NAME    ?= jenkinsforge
IMAGE_TAG   ?= $(shell git rev-parse --short HEAD 2>/dev/null || echo local)
REGISTRY    ?= $(APP_NAME)
FULL_IMAGE   = $(REGISTRY):$(IMAGE_TAG)

.PHONY: help install test lint sast dependency-scan \
        docker-build trivy sbom sign verify clean all

help: ## Show this help
	@awk 'BEGIN{FS=":.*##";printf "\nUsage: make \033[36m<target>\033[0m\n\nTargets:\n"} \
	/^[a-zA-Z_-]+:.*##/{printf "  \033[36m%-22s\033[0m %s\n",$$1,$$2}' $(MAKEFILE_LIST)

# ── Setup ──────────────────────────────────────────────────────────────────────

install: ## Install dev dependencies into the active Python env
	cd app && pip install -r requirements-dev.txt

# ── CI stages ─────────────────────────────────────────────────────────────────

test: ## Run unit tests  (mirrors: Unit Test stage)
	bash scripts/test.sh

lint: ## Run ruff linter  (mirrors: Lint stage)
	bash scripts/lint.sh

sast: ## Run Semgrep SAST  (mirrors: SAST stage)
	bash scripts/sast.sh

dependency-scan: ## Scan Python deps for CVEs  (mirrors: Dependency Scan stage)
	bash scripts/dependency-scan.sh

# ── Container stages ───────────────────────────────────────────────────────────

docker-build: ## Build Docker image  (mirrors: Docker Build stage)
	REGISTRY=$(REGISTRY) IMAGE_TAG=$(IMAGE_TAG) bash scripts/build.sh

trivy: ## Trivy vulnerability scan  (mirrors: Trivy Scan stage)
	bash scripts/trivy-scan.sh "$(FULL_IMAGE)"

sbom: ## Generate SBOM  (mirrors: SBOM stage)
	bash scripts/sbom.sh "$(FULL_IMAGE)"

sign: ## Sign image with Cosign  (mirrors: Sign Image stage)
	@[ -f cosign.key ] || { echo "cosign.key not found — run: cosign generate-key-pair"; exit 1; }
	COSIGN_PASSWORD="${COSIGN_PASSWORD}" bash scripts/sign.sh "$(FULL_IMAGE)" cosign.key

verify: ## Verify deployment health  (mirrors: Verify stage)
	@[ -n "$(DEPLOY_HOST)" ] || { echo "Set DEPLOY_HOST=<host>"; exit 1; }
	bash scripts/verify.sh "$(DEPLOY_HOST)"

# ── Compound targets ───────────────────────────────────────────────────────────

ci: test lint sast dependency-scan ## Run all CI gates (no Docker required)

security: docker-build trivy sbom ## Build + scan + SBOM

all: ci security ## All local stages

# ── Development ────────────────────────────────────────────────────────────────

run: ## Run the application locally
	cd app && uvicorn src.main:app --reload --port 8000

run-docker: docker-build ## Run the Docker image locally
	docker run --rm -p 8000:8000 --name $(APP_NAME)-local "$(FULL_IMAGE)"

clean: ## Remove local Docker image and reports
	docker rmi "$(FULL_IMAGE)" 2>/dev/null || true
	rm -f reports/*.xml reports/*.json reports/*.sarif reports/*.txt
	echo "Cleaned"
