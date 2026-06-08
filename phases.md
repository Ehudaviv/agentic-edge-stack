# MLOps Assessment - The Agentic Edge Stack: Implementation Phases

This document details the phases we will follow to complete the AI Platform DevOps Engineer Assessment for the **Agentic Edge Stack** using the chosen architecture.

## Selected Stack
* **Agent Framework**: Native Python tool-calling loop.
* **Kubernetes Cluster**: `k3d` (K3s in Docker) with 1 control plane, 2 worker nodes.
* **Inference Server**: `Ollama` with Qwen 2.5 (0.5B/1.5B) quantized model.
* **Vector DB**: `Qdrant`.
* **Advanced Tracks**: All Tracks (A: Advanced Quantization/Inference Tuning, B: Observability Grafana/Prometheus/Loki, C: Chaos testing, D: GitOps CD via ArgoCD, E: Load testing via Locust).

---

## Phase 1: Backend Engineering — The FastAPI Agent Service
* **Objective**: Build a Python backend service implementing the streaming SSE `/chat` endpoint and tool calling.
* **Tasks**:
  * [x] Set up requirements and local dependencies.
  * [x] Write `src/app/config.py` to parse config from environment variables.
  * [x] Write `src/app/tools.py` containing Qdrant search and mock lookup tools.
  * [x] Write `src/app/agent.py` implementing the native tool-calling agent loop.
  * [x] Write `src/app/main.py` with `/chat` streaming SSE endpoint, `/health` endpoint, and Prometheus instrumentator integration.
  * [x] Write `scripts/validate_agent.py` to test the API locally with mocked components.

## Phase 2: Local Cluster Provisioning & Containerization
* **Objective**: Provision the local environment (k3d, registry) and containerize the agent app.
* **Tasks**:
  * [x] Write `src/Dockerfile` using secure multi-stage builds.
  * [x] Write `manifests/k3d-config.yaml` to specify multi-node topology and port mappings.
  * [x] Create `scripts/bootstrap.sh` to automate:
    * Spinning up the k3d cluster.
    * Setting up the local docker registry and linking it to k3d.
    * Building the agent Docker image and pushing it to the registry.

## Phase 3: Declarative Deployments & GitOps (Kubernetes Core)
* **Objective**: Deploy all core applications using a packaged Helm Chart synced via ArgoCD.
* **Tasks**:
  * [x] Set up ArgoCD installation manifests (`gitops/argocd-install.yaml`).
  * [x] Package the core applications (Agent, Ollama, Qdrant) into a unified Helm Chart (`manifests/charts/agentic-edge-stack`).
  * [x] Write ArgoCD `Application` spec (`gitops/application.yaml`) pointing to our local Helm Chart.
  * [x] Configure Helm templates with ConfigMaps/Secrets, resource requests/limits, HPA, and StatefulSets.

## Phase 4: Advanced Tracks & Observability Setup
* **Objective**: Set up observability, load testing, chaos scenarios, and model optimizations.
* **Tasks**:
  * [ ] **Track A**: Inject Modelfile configuration for Ollama (e.g. quantization parameters, max token configurations).
  * [ ] **Track B**: Deploy Prometheus + Grafana and Loki/Promtail (or Grafana Agent) to scrape agent `/metrics` and aggregate container logs. Configure custom dashboards.
  * [ ] **Track C**: Write `scripts/chaos_test.sh` to inject pod failures, high CPU load, and network latency.
  * [ ] **Track E**: Write `tests/load_test.py` with Locust simulating streaming concurrent `/chat` requests.

## Phase 5: Verification, Tuning, and README Documentation
* **Objective**: Run verification scripts, analyze metrics, and prepare the submission.
* **Tasks**:
  * [ ] Run the end-to-end integration flow.
  * [ ] Execute Locust load tests and check if HPA dynamically scales agent replicas.
  * [ ] Run Chaos Engineering scenarios and monitor Grafana.
  * [ ] Document the architecture, prerequisites, setup instructions, and validation details in `README.md`.
