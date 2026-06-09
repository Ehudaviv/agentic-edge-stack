# The Agentic Edge Stack

A locally simulated, production-ready MLOps infrastructure built on Kubernetes (K3s via `k3d`) hosting a FastAPI AI Agent service, Ollama inference engine, and Qdrant distributed vector database.

This project showcases a complete end-to-end cloud-native implementation of local LLM serving, dynamic tool calling, real-time Server-Sent Events (SSE) token streaming, GitOps, observability, load testing, and chaos testing.

---

## Repository Architecture

```
.
├── README.md                          # Main documentation
├── phases.md                          # Interactive project progress tracker
├── interview_notes.md                 # Detailed design justifications & interview prep
├── scripts/
│   ├── bootstrap.sh                   # Automates cluster spin-up, registries, and deployments
│   ├── chaos_test.sh                  # Chaos engineering scenarios script
│   └── validate_agent.py              # Local FastAPI offline validation script
├── src/
│   ├── Dockerfile                     # Multi-stage container file for FastAPI app
│   ├── requirements.txt               # App dependencies
│   └── app/
│       ├── main.py                    # FastAPI app (streaming SSE, /health, /metrics)
│       ├── agent.py                   # Native tool-calling agent loop (Ollama API client)
│       ├── config.py                  # Pydantic Configuration loading from Env vars
│       └── tools.py                   # Qdrant client & mock database lookup logic
├── gitops/                            # GitOps CD automation
│   ├── application.yaml               # ArgoCD Application spec
│   └── argocd-install.yaml            # ArgoCD core controller manifests
├── manifests/                         # Declarative Kubernetes Manifests (ArgoCD synced)
│   ├── k3d-config.yaml                # k3d Multi-node cluster configuration
│   ├── agent-app/                     # FastAPI app manifests (Deployment, HPA, Service)
│   ├── inference/                     # Ollama manifests (StatefulSet, Service, Modelfile config)
│   ├── vector-db/                     # Qdrant manifests (StatefulSet, Service)
│   └── monitoring/                    # Observability helm charts (Prometheus/Grafana/Loki)
└── tests/
    └── load_test.py                   # Locust load test script
```

---

## Features Implemented

* **FastAPI AI Agent**: Real-time streaming `/chat` endpoint (SSE), built-in resilient tool calling.
* **Declarative K8s Deployments**: Managed via ArgoCD GitOps pipelines.
* **Auto-Scaling**: HPA configured for the FastAPI service.
* **Local Model Serving**: Ollama executing optimized Qwen 2.5 models on CPU.
* **Vector Store**: Qdrant database with fallback support for local mock databases.
* **Full Observability**: Prometheus and Grafana for metrics; Loki and Promtail for logs.
* **Resiliency**: Dedicated Chaos Engineering test script to validate fault tolerance.
* **Load Testing & Scaling**: Locust load testing script simulating concurrent users to verify HPA autoscaling.

---

## Developer Experience & Automated Lifecycle (Makefile)

To simplify operations and support E2E automated evaluation, we provide a root-level `Makefile` that handles the complete environment lifecycle.

### Makefile Commands Summary

Run `make help` to inspect available targets:
* **`make help`**: Prints the help summary menu.
* **`make venv`**: Prepares the local virtualenv and installs dependencies (FastAPI, Qdrant Client, Locust, etc.).
* **`make clean`**: Deletes the local k3d cluster and registry, and stops lingering port-forwards.
* **`make bootstrap`**: Creates the cluster, builds/registers the Agent image, pre-pulls/caches all stack and monitoring images, and deploys ArgoCD.
* **`make monitoring`**: Deploys kube-prometheus-stack and loki-stack.
* **`make wait`**: Blocks execution until all pods are fully `Ready` across all cluster namespaces.
* **`make up`**: Runs `bootstrap`, `monitoring`, and `wait` sequentially (Full Setup).
* **`make test`**: Runs local mock offline backend validation.
* **`make test-cluster`**: Sends a POST request from the host to the NodePort service (`http://localhost:30000/chat`) to verify streaming.
* **`make stress`**: Runs Locust load tests in headless mode (parameters like `USERS`, `SPAWN_RATE`, and `RUN_TIME` are configurable).
* **`make chaos`**: Runs resiliency tests injecting Vector DB and Agent replica outages.
* **`make all`**: Runs `clean`, `up`, `test`, `test-cluster`, `stress`, and `chaos` sequentially.

---

## Quick Start (Evaluation Guide)

### 1. Prerequisites
* Docker
* k3d (`wget -qO - https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | TAG=v5.6.0 bash`)
* Helm (`curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash`)
* Python 3.11+

### 2. Stack Deployment
To spin up a new cluster, build the container, cache all required images locally, install ArgoCD + applications, deploy monitoring, and block until everything is fully online:
```bash
make up
```

### 3. Verify Applications & Streaming API
Run the offline validation followed by E2E streaming checks:
```bash
# Offline backend API checks
make test

# In-Cluster NodePort streaming API checks
make test-cluster
```

### 4. Verify Observability & Dashboards
* **Access Grafana Dashboard**:
  * Navigate to [http://localhost:30030](http://localhost:30030)
  * **Username**: `admin` | **Password**: `admin`
  * Open the **MLOps - Agentic Edge Stack** dashboard.
  * You will see CPU/Memory allocations, FastAPI throughput/latency metrics, and Loki log streams for both the AI Agent and Ollama.

### 5. Verify Resiliency (Chaos Testing)
Execute the chaos injection suite to assert application fallback and Kubernetes self-healing:
```bash
make chaos
```
* **Scenario 1 (DB Outage)**: Deletes the `qdrant-0` pod. Queries will gracefully fallback to local mock facts during the database outage.
* **Scenario 2 (Pod Outage)**: Forcefully deletes an active `agent-app` replica. Client requests will route to other healthy replicas with zero downtime.

### 6. Verify Load Scaling (Stress Testing)
Execute load tests headlessly to trigger HPA scaling (replicas scale from 2 up to 10):
```bash
make stress RUN_TIME=2m
```
* Monitor active scaling in terminal: `kubectl get hpa agent-hpa -n agentic-edge-stack -w`
* Observe new container lines appearing on the CPU and Memory charts in Grafana.
