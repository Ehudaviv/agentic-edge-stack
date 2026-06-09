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

### Step 5: Deploy & Verify Observability (Phase 4, Track B)

The observability stack gathers FastAPI metrics, aggregates logs, and provisions a custom GitOps-synced dashboard automatically. 

To deploy the Prometheus, Grafana, and Loki monitoring stacks using the local offline tarballs, execute:

```bash
./scripts/deploy_monitoring.sh
```


#### Verification Steps:

1. **Check that monitoring pods are running**:
   ```bash
   kubectl get pods -n monitoring
   ```

2. **Access the Grafana Dashboard**:
   * Open your browser to [http://localhost:30030](http://localhost:30030).
   * **Username**: `admin`
   * **Password**: `admin`

3. **Verify metrics collection (FastAPI)**:
   * Go to **Explore** (compass icon) in the Grafana sidebar.
   * Select **Prometheus** from the top data source dropdown.
   * In the query field, search for `fastapi_requests_total` (or `http_requests_total`) and click **Run Query**. This confirms that the Prometheus operator `PodMonitor` is actively scraping FastAPI metrics.

4. **Verify log aggregation (Loki)**:
   * Select **Loki** from the data source dropdown.
   * Enter the query `{namespace="agentic-edge-stack", container="agent-app"}` and click **Run Query**. You will see container logs aggregated across all active replicas, allowing you to trace requests and exceptions.

5. **Verify the Custom MLOps Dashboard**:
   * In the Grafana sidebar, click on **Dashboards** (or go to `http://localhost:30030/dashboards`).
   * Select the **MLOps - Agentic Edge Stack** dashboard from the list.
   * Confirm that it renders the 10 custom panels:
     * **FastAPI Agent Pods CPU Utilization**: Metric `container_cpu_usage_seconds_total` tracking application CPU.
     * **FastAPI Agent Pods Memory Utilization**: Metric `container_memory_working_set_bytes` tracking application RAM.
     * **FastAPI Agent HTTP Request Rate**: Request throughput split by HTTP method, handler, and status code.
     * **FastAPI Agent /chat Request Latency**: The 95th and 99th percentile latency distribution of streaming API calls.
     * **Ollama & Qdrant Resource Footprints**: Individual CPU and Memory charts for the LLM runner and Vector DB.
     * **Loki Logs**: Embedded panels showing real-time log outputs for both FastAPI and Ollama containers.

### Step 6: Run Chaos Resiliency Tests (Phase 4, Track C)

We provide an automated chaos injection script that tests the fault-tolerance and self-healing behaviors of both the FastAPI Agent and the database pods.

To run the automated chaos tests, execute:
```bash
./scripts/chaos_test.sh
```

#### What the Chaos Test Verifies:
1. **Database Outage Resilience (Scenario 1)**:
   * The script launches a background client stream querying the agent `/chat` endpoint, then deletes the active database pod (`qdrant-0`).
   * **Resilience Behavior**: The agent automatically fails over to the mock fact lookup database inside `tools.py`. The stream completes successfully without throwing HTTP 5xx errors or dropping client connections. Kubernetes automatically restarts the `qdrant-0` pod, and the database heals back to full readiness.
2. **FastAPI Agent Pod Failure (Scenario 2)**:
   * The script queries `/chat` continuously while forcefully deleting one of the active agent replica pods.
   * **Resilience Behavior**: Kubernetes immediately reroutes traffic to the other healthy replica pod. Client requests experience zero service interruption. The deployment controller automatically schedules a new pod to restore the replica count back to the HPA minimum.

### Step 7: Run Automated Load Tests & HPA Scaling (Phase 4, Track E)

We use **Locust** to simulate heavy concurrent load on the streaming `/chat` endpoint and verify that the Horizontal Pod Autoscaler (HPA) triggers pod scale-up.

#### How to run the Load Test:
1. Make sure you have activated the virtual environment:
   ```bash
   source .venv/bin/activate
   ```
2. Start the Locust test tool using the helper script:
   ```bash
   ./scripts/run_load_test.sh
   ```
   *By default, this will start the Locust Web UI server.*
3. Open your browser and navigate to **`http://localhost:8089`**.
4. Configure the test parameters:
   * **Number of users**: `100` (concurrent users)
   * **Spawn rate**: `10` (users spawned per second)
   * **Host**: `http://localhost:30000` (FastAPI Agent NodePort)
5. Click **Start swarming** to begin the load test.

#### Headless CLI Alternative:
To run the load test directly in your terminal for exactly 2 minutes without opening the Web UI:
```bash
./scripts/run_load_test.sh headless
```

#### What to Verify during Load Testing:
1. **Locust UI Metrics**: Under the **Statistics** tab, observe separate tracked rows for `/chat [TTFT]` (measuring time to first token) and `/chat [Total Stream]` (measuring the full stream response duration) to inspect streaming performance.
2. **HPA Autoscaling**:
   * Open a terminal and watch the HPA resource utilization:
     ```bash
     kubectl get hpa agent-hpa -n agentic-edge-stack -w
     ```
   * Under heavy concurrent query streams (100 users), you will see the CPU utilization percentage exceed the target threshold (`50%`).
   * The replica count will scale up from `2` to `3` or higher (up to `10`) to distribute the load across multiple FastAPI container instances.
3. **Autoscaling Visualizations**:
   * Access your Grafana dashboard at `http://localhost:30030/dashboards`.
   * Open the **MLOps - Agentic Edge Stack** dashboard.
   * Observe the **FastAPI Agent Pods CPU Utilization** and **FastAPI Agent Pods Memory Utilization** charts showing new pod lines as they scale up, alongside the overall increase in request rate and latency quantiles.
