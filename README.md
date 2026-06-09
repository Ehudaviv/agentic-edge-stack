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

---

## Quick Start (Local Development)

### Prerequisites
* Docker
* k3d (`wget -qO - https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | TAG=v5.6.0 bash`)
* Helm (`curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash`)
* Python 3.11+

### Step 1: Validate FastAPI Backend Locally
Validate that the FastAPI SSE chat server works locally using mock data:
```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r src/requirements.txt
python3 scripts/validate_agent.py
```

### Step 2: Bootstrap Local Cluster, Registry, Helm Chart, and ArgoCD (Phases 2 & 3)
To create the cluster, build and push the FastAPI container, import offline images, install ArgoCD, and deploy the stack using our Helm Chart, run:
```bash
./scripts/bootstrap.sh
```
This script automates the complete lifecycle. After it finishes successfully, check that all pods are running:
```bash
kubectl get pods -n agentic-edge-stack
kubectl get pods -n argocd
```

### Step 3: Verify Deployments & GitOps (Phase 3)

1. **Verify Services connectivity**:
   Send a POST query directly to the FastAPI agent running in the cluster at NodePort `30000`:
   ```bash
   curl -i -N -X POST http://localhost:30000/chat \
     -H "Content-Type: application/json" \
     -d '{"message": "What is k3d?"}'
   ```
   *Expected Output*: Should stream back tokens explaining what `k3d` is, dynamically calling the local database/mock tool.

2. **Access ArgoCD Dashboard**:
   Open your browser and navigate to `http://localhost:30080` (mapped to ArgoCD's `argocd-server` NodePort).
   * **Username**: `admin`
   * **Password Retrieval Command**:
     ```bash
     kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
     ```
   * **Bootstrapped Password**: `iUb9z8gHjfbeqjaX`
   
   You can sync changes dynamically via GitOps by applying the application manifest:
   ```bash
   kubectl apply -f gitops/application.yaml
   ```

### Step 4: Verify Custom Inference Tuning (Phase 4, Track A)

Once deployed, you can verify that the custom `Modelfile` parameters and the tuned model have been initialized successfully:

1. **Verify the tuned model exists**:
   ```bash
   kubectl exec -it ollama-0 -n agentic-edge-stack -- ollama list
   ```
   *Expected Output*: Should show both the base model `qwen2.5:0.5b` and the tuned model `tuned-agent`.

2. **Inspect the tuned model details and system parameters**:
   ```bash
   kubectl exec -it ollama-0 -n agentic-edge-stack -- ollama show tuned-agent
   ```
   *Expected Output*: Displays the system prompt and custom parameters (like `temperature 0.2` and `num_ctx 2048`) defined in the Modelfile.

3. **Verify the Agent is running queries against the tuned model**:
   Perform a SSE chat query and inspect the agent application logs to verify it targets `tuned-agent`:
   ```bash
   kubectl logs -f deployment/agent-app -n agentic-edge-stack -c agent
   ```
