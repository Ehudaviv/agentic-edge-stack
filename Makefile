# Makefile for Agentic Edge Stack lifecycle management
.PHONY: help venv bootstrap monitoring wait up clean clean-infra up-infra test test-cluster stress chaos all

# Configurable load testing parameters
USERS ?= 100
SPAWN_RATE ?= 10
RUN_TIME ?= 2m

# Default target: display help information
help:
	@echo "========================================================================="
	@echo "                  Agentic Edge Stack Management Commands"
	@echo "========================================================================="
	@echo "Available commands:"
	@echo "  make help          - Display this help message"
	@echo "  make venv          - Create Python virtual environment and install dependencies"
	@echo "  make bootstrap     - Provision the cluster registry, k3d, and core application"
	@echo "  make monitoring    - Deploy observability stack (Prometheus, Grafana, Loki)"
	@echo "  make wait          - Block until all pods in all namespaces are fully Ready"
	@echo "  make up            - Build/provision cluster, deploy monitoring, and wait for readiness"
	@echo "  make up-infra      - Fast redeploy of app and monitoring (keep cluster/registry)"
	@echo "  make clean         - Destroy cluster, registry, and terminate port-forwards"
	@echo "  make clean-infra   - Teardown only the app and monitoring namespaces (keep cluster)"
	@echo "  make test          - Run local FastAPI offline validation tests using mock"
	@echo "  make test-cluster  - Query the cluster NodePort API directly to verify E2E streaming"
	@echo "  make stress        - Run Locust load tests in headless mode (headless)"
	@echo "                       (Options: USERS=100 SPAWN_RATE=10 RUN_TIME=2m)"
	@echo "  make chaos         - Run automated infrastructure and pod chaos engineering tests"
	@echo "  make all           - E2E Lifecycle: clean, bootstrap, monitor, wait, test, stress, chaos"
	@echo "========================================================================="

# 1. Setup Python virtual environment
venv:
	@echo "Checking Python virtual environment..."
	@if [ ! -d ".venv" ]; then \
		echo "Creating virtual environment .venv..."; \
		python3 -m venv .venv; \
	fi
	@echo "Installing/updating backend requirements..."
	@.venv/bin/pip install -r src/requirements.txt
	@echo "Installing/updating locust load testing tool..."
	@.venv/bin/pip install locust

# 2. Bootstrap cluster and registry
bootstrap:
	@echo "Executing cluster bootstrapping..."
	@chmod +x scripts/bootstrap.sh
	@INFRA_ONLY=$${INFRA_ONLY:-$(INFRA_ONLY)} ./scripts/bootstrap.sh

# 3. Deploy monitoring stack
monitoring:
	@echo "Executing monitoring deployments..."
	@chmod +x scripts/deploy_monitoring.sh
	@./scripts/deploy_monitoring.sh

# 4. Wait for all pods in all namespaces to be ready
wait:
	@chmod +x scripts/wait_for_ready.sh
	@./scripts/wait_for_ready.sh

# 5. Up: Full Provisioning Sequence
up: bootstrap monitoring wait
	@echo "Deployment up and fully healthy!"

# 6. Clean: Teardown environment
clean:
	@if [ "$${INFRA_ONLY:-$(INFRA_ONLY)}" = "true" ]; then \
		echo "Tearing down application and monitoring namespaces (keeping cluster)..."; \
		kubectl delete -f gitops/application.yaml --ignore-not-found || true; \
		kubectl delete namespace agentic-edge-stack || true; \
		kubectl delete namespace monitoring || true; \
	else \
		echo "Tearing down cluster (keeping local registry container for persistent cache)..."; \
		k3d cluster delete agentic-edge-stack || true; \
	fi
	@echo "Terminating any lingering kubectl port-forward or locust processes..."
	@pkill -f "[p]ort-forward" || true
	@pkill -f "[l]ocust" || true
	@echo "Environment cleaned."

clean-all: clean
	@echo "Tearing down local registry container..."
	@k3d registry delete registry.localhost || true

clean-infra:
	@$(MAKE) clean INFRA_ONLY=true

up-infra:
	@$(MAKE) up INFRA_ONLY=true

# 7. Local Offline Test
test: venv
	@echo "Running local FastAPI mock validation..."
	@.venv/bin/python scripts/validate_agent.py

# 8. In-Cluster API NodePort Test
test-cluster:
	@echo "Testing chat endpoint on the cluster NodePort (http://localhost:30000/chat)..."
	@curl -s -N -X POST http://localhost:30000/chat \
		-H "Content-Type: application/json" \
		-d '{"message": "What is k3d?"}' | grep -q "token" && echo "Success: Cluster Agent is responsive!" || (echo "Failed: Cluster Agent is not responding correctly." && exit 1)

# 9. Stress/Load Test
stress: venv
	@echo "Running Locust load test in headless mode..."
	@USERS=$(USERS) SPAWN_RATE=$(SPAWN_RATE) RUN_TIME=$(RUN_TIME) ./scripts/run_load_test.sh headless

# 10. Chaos Engineering Test
chaos:
	@echo "Running chaos engineering scripts..."
	@chmod +x scripts/chaos_test.sh
	@./scripts/chaos_test.sh

# 11. Complete E2E Automation Pipeline
all: clean up test test-cluster stress chaos
	@echo "========================================================="
	@echo "       All E2E lifecycle tasks completed successfully!"
	@echo "========================================================="
