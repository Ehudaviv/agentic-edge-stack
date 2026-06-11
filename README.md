# The Agentic Edge Stack

A locally simulated, production-ready MLOps infrastructure built on Kubernetes (K3s via `k3d`) hosting a FastAPI AI Agent service, Ollama inference engine, and Qdrant distributed vector database.

This project showcases a complete end-to-end cloud-native implementation of local LLM serving, dynamic tool calling, real-time Server-Sent Events (SSE) token streaming, GitOps, observability, load testing, and chaos testing.

---

## Repository Architecture

```
.
├── Makefile                           # Root orchestrator (venv, up, clean, test, stress, chaos, all)
├── README.md                          # Main documentation & evaluation guide
├── phases.md                          # Interactive project progress tracker
├── interview_notes.md                 # Detailed design justifications & interview prep
├── Mission - AI Platform DevOps Engineer Assessment - The Agentic Edge Stack.txt # Original assessment description
├── scripts/                           # Automation & validation scripts
│   ├── bootstrap.sh                   # Cluster setup, image caching/node importing, and ArgoCD rollout
│   ├── deploy_monitoring.sh           # Installs observability stack (Prometheus, Grafana, Loki)
│   ├── wait_for_ready.sh              # Non-interactive pod health wait verification loop
│   ├── validate_agent.py              # Local FastAPI offline validation script
│   ├── run_load_test.sh               # Headless or UI runner for Locust load tests
│   └── chaos_test.sh                  # Chaos engineering scenarios script
├── src/                               # FastAPI application source code
│   ├── Dockerfile                     # Secure multi-stage app container image configuration
│   ├── requirements.txt               # App library dependencies
│   └── app/                           
│       ├── main.py                    # FastAPI service (SSE streaming, health & prometheus endpoints)
│       ├── agent.py                   # Native LLM tool-calling async agent loop
│       ├── config.py                  # Pydantic settings configuration loader
│       └── tools.py                   # Qdrant DB connector with mock lookup fallback
├── gitops/                            # GitOps CD automation configs
│   ├── application.yaml               # ArgoCD Application mapping local Helm chart
│   └── argocd-install.yaml            # ArgoCD platform manifests
├── manifests/                         # Declarative Kubernetes configuration
│   ├── k3d-config.yaml                # Declarative k3d multi-node topography configurations
│   ├── charts/                        
│   │   └── agentic-edge-stack/        # Unified Helm Chart for the core stack
│   │       ├── Chart.yaml             # Chart metadata
│   │       ├── values.yaml            # Configurable service parameters & resource specs
│   │       └── templates/             # Deployments, StatefulSets, HPA, ConfigMaps, Secrets, PodMonitor
│   └── monitoring/                    # Observability Helm configuration and directory charts
│       ├── kube-prometheus-stack/     # Unpacked Kube-Prometheus stack chart (Option A GitOps)
│       ├── loki-stack/                # Unpacked Loki stack directory chart (Option A GitOps)
│       ├── prometheus-values.yaml     # Custom Prometheus/Grafana integrations values
│       └── loki-values.yaml           # Loki offline adjustments values
└── tests/                             # E2E load/performance testing
    └── load_test.py                   # Locust load test scenarios hitting streaming SSE API
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
* **`make clean-infra`**: Teardowns only the application (`agentic-edge-stack`) and monitoring (`monitoring`) namespaces. Keeps the k3d cluster, registry, and all pre-imported offline images intact.
* **`make bootstrap`**: Creates the cluster, builds/registers the Agent image, pre-pulls/caches all stack and monitoring images, and deploys ArgoCD.
* **`make monitoring`**: Deploys kube-prometheus-stack and loki-stack.
* **`make wait`**: Blocks execution until all pods are fully `Ready` across all cluster namespaces (with robust namespace-polling).
* **`make up`**: Runs `bootstrap`, `monitoring`, and `wait` sequentially (Full Setup).
* **`make up-infra`**: Fast redeploy of the application code, ArgoCD application, and monitoring Helm charts without recreating the cluster, saving minutes of image import time.
* **`make test`**: Runs local mock offline backend validation.
* **`make test-cluster`**: Sends a POST request from the host to the NodePort service (`http://localhost:30000/chat`) to verify streaming.
* **`make stress`**: Runs Locust load tests in headless mode (parameters like `USERS`, `SPAWN_RATE`, and `RUN_TIME` are configurable).
* **`make chaos`**: Runs resiliency tests injecting Vector DB and Agent replica outages.
* **`make all`**: Runs `clean`, `up`, `test`, `test-cluster`, `stress`, and `chaos` sequentially.

---

## Fast Development Loop (Infrastructure-Only Mode)

If you are modifying the application code in `src/` or editing manifests, you don't need to rebuild the cluster and re-import all offline container images. You can use the fast infrastructure-only lifecycle targets:

```bash
# Tear down application and monitoring namespaces only:
make clean-infra

# Rebuild the FastAPI Agent container, deploy ArgoCD application and monitoring stack:
make up-infra
```
This is fully automated and reduces the dev cycle reset time to seconds.

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
  * **Username**: `admin`
  * **Password Retrieval Command**:
    ```bash
    kubectl -n monitoring get secret prometheus-grafana -o jsonpath='{.data.admin-password}' | base64 --decode ; echo
    ```
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


