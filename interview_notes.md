# MLOps Interview Notes & Architectural Decisions

This document tracks our architectural decisions, justifications, and key concepts for the **Agentic Edge Stack** assessment. Use this to prepare for your MLOps interview.

---

## 1. Architectural Decisions & Justifications

### A. Python Agent: Native Loop vs. LangGraph/LangChain
* **Our Choice**: **Native Python tool-calling loop**
* **Justification**:
  * **Simplicity & Performance**: A native implementation has zero framework overhead, resulting in faster container startup times, lower memory footprint, and easier debugging of streaming responses.
  * **Control over SSE**: Implementing Server-Sent Events (SSE) streaming is direct and transparent, avoiding potential buffering or integration issues common in third-party wrappers.
  * **Interview Context**: In production MLOps, keeping the service layer lightweight is critical. Demonstrating that you can write a lightweight tool-calling loop shows deep understanding of the underlying LLM JSON specifications without hiding behind framework abstractions.

### B. Cluster Provisioning: K3d (K3s) vs. Kind vs. Minikube
* **Our Choice**: **K3d (K3s in Docker)**
* **Justification**:
  * **Extremely Lightweight**: K3s replaces etcd with a lightweight SQLite database (by default) and wraps core Kubernetes components into a single binary. It uses less than half the memory of a typical vanilla Kubernetes distribution (like Kind or Minikube).
  * **Speed**: K3d clusters spin up and down in seconds, making local development loops and automated bootstrapping extremely rapid.
  * **Production Parity**: K3s is a CNCF-certified Kubernetes distribution, meaning manifests written for it are fully compatible with production-grade upstream Kubernetes (EKS, GKE, AKS).

### C. Inference Server: Ollama vs. vLLM
* **Our Choice**: **Ollama**
* **Justification**:
  * **Local Resource Friendly**: Ollama is specifically optimized for running models on local CPU/GPU setups with minimal RAM. It handles GGUF quantization formats out-of-the-box.
  * **vLLM Trade-offs**: While vLLM is the gold standard for high-concurrency production serving (supporting PagedAttention and continuous batching), it has massive memory overhead (requiring large GPU VRAM or massive system RAM even for small models) and is complex to configure for CPU-only local environments.
  * **Ease of Model Management**: Ollama's `Modelfile` syntax allows us to declaratively define system prompts, templates, and parameters (Track A) like a Dockerfile.

### D. Vector Database: Qdrant vs. Weaviate
* **Our Choice**: **Qdrant**
* **Justification**:
  * **Rust-based Efficiency**: Written in Rust, Qdrant has an extremely small memory footprint and very low query latency.
  * **SDK Maturity**: The Python SDK is intuitive, simple to set up, and supports asynchronous operations natively.
  * **Ease of Clustering**: Qdrant can easily run as a single instance or distributed cluster on Kubernetes via standard Helm charts or StatefulSets.

### E. Resilient Tool-Calling (Handling Small LLM Hallucinations)
* **Our Choice**: Defensive, custom arguments parser in the FastAPI service.
* **Justification**:
  * **Edge-case**: Small localized models (such as Qwen 2.5 0.5B under resource limits) sometimes hallucinate tool arguments. Instead of outputting a clean string for parameters, they may output a dictionary containing the property schema description (e.g. `{'query': {'type': 'string', 'description': '...'}}`).
  * **Our Solution**: We implemented recursive dictionary parsing to detect nested properties and filter out schema metadata. If no clean search query can be extracted, the agent automatically falls back to using the user's raw message as the database query, rather than throwing an `AttributeError` like `'dict' object has no attribute 'lower'`.
  * **Interview Context**: Demonstrates operational reliability in production. LLM outputs are unpredictable; building robust guardrails at the API gateway layer prevents cascading errors in down-stream services.

---

## 2. Core MLOps Concepts for the Interview

### What is Server-Sent Events (SSE) for Streaming?
* **Concept**: SSE is a HTTP standard allowing a server to push real-time updates to a client over a single HTTP connection.
* **Why it matters**: For GenAI/LLM applications, streaming tokens as they are generated reduces **Time-To-First-Token (TTFT)**, improving user experience dramatically compared to waiting for the full response (which can take 10+ seconds).
* **SSE vs WebSockets**: SSE is unidirectional (server-to-client) and runs over standard HTTP, making it simpler, easier to load balance, and more resilient (auto-reconnects) than bidirectional WebSockets.

### What is Horizontal Pod Autoscaling (HPA)?
* **Concept**: HPA automatically scales the number of Pods in a replication controller, deployment, or replica set based on observed CPU utilization (or custom metrics).
* **Why it matters**: MLOps workloads are highly variable. By using HPA, we ensure the FastAPI agent scales out to handle spikes in traffic and scales down to save costs when idle.

### LLM Quantization Formats & Trade-offs (Track A)
Quantization reduces the precision of model weights (e.g., from 16-bit floating point `FP16` to 4-bit or 8-bit integers) to compress the model size and lower the VRAM/RAM required for serving.

1. **GGUF (GPT-Generated Unified Format)**:
   * **Target Hardware**: Optimally designed for CPU-only or hybrid CPU+GPU systems.
   * **Mechanism**: A unified single-file binary format that supports *split-offloading* (loading part of the layers into GPU VRAM and keeping the rest in system RAM).
   * **Pros/Cons**: Extremely flexible for local execution. Minor latency degradation when splitting across memory architectures, but makes large model execution possible on non-specialized hardware.
   * **Our Usage**: Ollama uses GGUF natively. We run a 4-bit quantized Qwen 2.5 (0.5B) model, which only requires around 350-400MB of total memory, running at exceptionally high token throughput on raw CPU nodes.

2. **AWQ (Activation-aware Weight Quantization)**:
   * **Target Hardware**: GPU-only environments (e.g., serving via vLLM or TensorRT-LLM).
   * **Mechanism**: Observes weight activations during training and protects the top 1% "salient" weights (which contain critical information) by keeping them in higher precision, while quantizing the remaining 99% to 4-bit.
   * **Pros/Cons**: Excellent accuracy preservation. Significant speedup on GPUs compared to generic quantization. Not suitable for CPU execution.

3. **GPTQ (Generalized Post-Training Quantization)**:
   * **Target Hardware**: GPU-only environments.
   * **Mechanism**: Employs mathematical layer-by-layer optimization (based on the Hessian matrix) to adjust the remaining weights after quantizing to minimize error.
   * **Pros/Cons**: Extremely fast token-generation speed (decoding throughput). AWQ generally performs slightly better at retaining model reasoning capability for very small models, but GPTQ is highly competitive.

4. **FP8 (8-bit Floating Point)**:
   * **Target Hardware**: Modern server-grade GPUs (NVIDIA Ada Lovelace, Hopper, Blackwell architectures).
   * **Mechanism**: Uses native 8-bit floating point representations (E4M3 or E5M2 formats) instead of integers.
   * **Pros/Cons**: Supported natively at the hardware level in Tensor Cores. Provides near-FP16 accuracy with a 2x reduction in memory footprint and high computation speed, with no post-training processing required.

---

### Inference Engine Parameter Tuning & Optimization (Track A)
In production, model serving engines must be tuned to maximize throughput and limit resource saturation. Through our custom `Modelfile` mounted in the cluster, we tuned the following:

* **`PARAMETER num_ctx 2048` (Context Window Size)**:
  * *Default*: Usually 4096 or 8192 tokens.
  * *MLOps Impact*: The memory occupied by the Key-Value (KV) cache grows linearly with the context length and batch size. Reducing the context size to 2048 significantly decreases the VRAM/RAM allocation footprint of the model runner, ensuring that multiple concurrent client requests do not cause out-of-memory (OOM) crashes on resource-constrained K3d worker nodes.
* **`PARAMETER temperature 0.2` (Creativity / Randomness)**:
  * *MLOps Impact*: Lower temperature values make the model output deterministic by selecting high-probability tokens. For AI agent architectures that rely on tool calling, deterministic outputs are critical to prevent tool parameter hallucination and schema parsing failures.
* **`PARAMETER num_predict 512` (Safety Token Cap)**:
  * *MLOps Impact*: Enforces a hard limit on the maximum number of tokens generated per request. This acts as a safety guardrail, preventing looping generation states (caused by small model confusion) from consuming CPU cycles and blocking the inference queue indefinitely.
* **`PARAMETER top_p 0.9` & `top_k 40` (Token Sampling Filters)**:
  * *MLOps Impact*: Controls the vocabulary candidate pool during generation, filtering out noisy, low-probability tokens to maintain output coherence.
* **`SYSTEM` Prompt Injection**:
  * *MLOps Impact*: Injects structural instructions directly at the model compiler layer rather than appending them in the API wrapper. This saves token overhead on every chat turn, reducing TTFT (Time-to-First-Token).

### Platform Observability & Log Aggregation (Track B)
To trace streaming requests and diagnose performance bottlenecks (e.g., latency spikes, tool failures), we deployed a standard production-grade monitoring stack.

1. **Prometheus Operator & ServiceMonitor/PodMonitor CRDs**:
   * **Concept**: The Prometheus Operator acts as a Kubernetes controller that monitors custom resources (`ServiceMonitor` or `PodMonitor`). Instead of manually configuring scraping endpoints in a massive global Prometheus config file, developers define a declarative `PodMonitor` next to their application deployment.
   * **Why it matters**: It scales metrics scraping dynamically. When new application pods scale out (via HPA), Prometheus automatically discovers and scrapes them via the pod selector labels, without needing manual configuration restarts.
   * **Our Usage**: We deployed a `PodMonitor` inside our application Helm chart targeting `app: agent-app` on port `http` (`8000`) at path `/metrics`.

2. **Loki & Promtail (Log Aggregation)**:
   * **Concept**: Loki is a horizontally-scalable, highly-available log aggregation system. Unlike Elasticsearch, Loki does not index the full-text of logs; instead, it only indexes label metadata (e.g., namespace, pod name, container), keeping storage costs extremely low.
   * **Promtail**: A logging agent deployed as a `DaemonSet` on every cluster node. It discovers local container log directories, attaches labels, and streams them to Loki.
   * **Why it matters**: In a dynamic microservice environment where pods are scaled or terminated by HPA, raw container logs are lost upon deletion. Centralizing logs in Loki enables aggregate search, log preservation, and dashboard tracing.

3. **Declarative Grafana Dashboard Provisioning (GitOps)**:
   * **Concept**: Instead of manually building dashboards in the Grafana UI (which is prone to configuration drift and loss on pod restart), we store the dashboard definition as a JSON schema inside a Kubernetes `ConfigMap`.
   * **Sidecar Watcher**: The Grafana pod runs a sidecar container (`kiwigrid/k8s-sidecar`) configured to watch all namespaces for ConfigMaps with the label `grafana_dashboard: "1"`. When added or updated, the sidecar downloads the JSON payload to `/tmp/dashboards` in the Grafana workspace, and triggers Grafana's dashboard reload API.
   * **Why it matters**: It achieves complete GitOps parity for monitoring. Dashboards are code, version-controlled, and instantly recreated during disaster recovery or multi-region promotions.
   * **Our Custom Panels & PromQL / LogQL Queries**:
     * *FastAPI CPU Utilization*: `sum(rate(container_cpu_usage_seconds_total{namespace="agentic-edge-stack", container="agent-app"}[2m])) by (pod)` (visualized in CPU cores).
     * *FastAPI Memory Utilization*: `sum(container_memory_working_set_bytes{namespace="agentic-edge-stack", container="agent-app"}) by (pod)` (visualized in IEC bytes).
     * *HTTP Request Rate*: `sum(rate(http_requests_total{namespace="agentic-edge-stack"}[2m])) by (handler, status, method)` (visualized in requests per second).
     * *HTTP Request Latency (Quantiles)*: `histogram_quantile(0.95, sum(rate(http_request_duration_seconds_bucket{namespace="agentic-edge-stack", handler="/chat"}[2m])) by (le))` (calculates the 95th and 99th percentile streaming latency).
     * *Ollama / Qdrant Resource Utilization*: Tracking CPU and memory of backends separately to pinpoint if bottlenecks stem from model execution (Ollama CPU-bound) or vector indexing (Qdrant).
     * *Loki Container Logs*: `{namespace="agentic-edge-stack", container="agent-app"}` and `{namespace="agentic-edge-stack", container="ollama"}` to provide side-by-side real-time log analysis next to metrics.
   * **MLOps Importance of These Metrics**:
     * **FastAPI Pod CPU & Memory**: Vital to verify Horizontal Pod Autoscaler (HPA) behavior. In resource-constrained edge deployments, CPU spikes trigger pod scaling, while memory monitoring prevents Out-Of-Memory (OOM) kills during heavy concurrent request spikes.
     * **HTTP Request Rates (SLA Volume)**: Identifies user traffic patterns, service load, and errors. A sudden surge in 5xx status codes highlights backend connectivity issues with Ollama or Qdrant.
     * **FastAPI Request Latency (p95 & p99)**: In a streaming LLM setup, tracking average latency is misleading because LLM token generation times vary heavily by query context. Percentiles (p95, p99) capture the worst-case user experience (latency bottlenecks, queue stalls) and help evaluate LLM response consistency.
     * **Ollama & Qdrant Resource Footprints**: Distinguishes application bottlenecks from infrastructure bottle-necks. Since LLM serving is heavily CPU/GPU bound, monitoring Ollama metrics indicates if we are queueing requests due to LLM hardware limitations, while Qdrant metrics track database indexing efficiency.
   * **Where logs are shown**:
     * Log streams are embedded directly **inside the Grafana Dashboard** on a dedicated row beneath the metrics charts. They use Loki's LogQL queries to pull container logs for both `agent-app` and `ollama` side-by-side. This allows developers to instantly correlate visual metric anomalies (e.g., a p99 latency spike or HTTP 500 error) with the exact container stderr/stdout logs in real time.

---

## 3. Interview Prep Questions
* *Be ready to explain how your `bootstrap.sh` ties the whole stack together.*
* *Be ready to explain why we use ConfigMaps for configuration and Secrets for API keys.*
* *Be ready to explain GitOps: "Why ArgoCD?" (ArgoCD continuously monitors the Git repository and reconciles any drift in the live Kubernetes cluster, enabling automated, declarative, version-controlled rollouts).*
* *Be ready to explain how Ollama handles custom model creation efficiently without duplicating storage or RAM/VRAM resource usage*:
  * **Layer Deduplication**: Ollama stores model parameters as content-addressable blobs (similar to Docker layers). Creating `tuned-agent` via a `Modelfile` with `FROM qwen2.5:0.5b` does *not* copy the weight files. Instead, it creates a lightweight pointer metadata file referencing the exact same weight blobs already present on disk.
  * **On-Demand Memory Allocation**: Ollama loads models dynamically only when they are queried. While idle, the base model `qwen2.5:0.5b` consumes zero RAM/VRAM. When `tuned-agent` is active, it occupies only its single instance allocation, leaving no double-loading footprints.

---

## 4. Created Files & Directories (Phases 1, 2, & 3)

* **`.gitignore`**: Configured to exclude `.venv/`, Python caches (`__pycache__/`, `*.pyc`), and debug logs from version control tracking.
* **`src/requirements.txt`**: Declares app dependencies (`fastapi`, `uvicorn`, `httpx`, `qdrant-client`, `prometheus-fastapi-instrumentator`, `sse-starlette`).
* **`src/app/config.py`**: Manages environment variable parsing with defaults using `pydantic-settings`.
* **`src/app/tools.py`**: Handles connection to Qdrant with dynamic mock lookup fallback.
* **`src/app/agent.py`**: Implements the native Python tool-calling loop using standard async HTTPX connections to Ollama.
* **`src/app/main.py`**: FastAPI server initialization, SSE `/chat` stream implementation, and Prometheus metrics binding.
* **`scripts/validate_agent.py`**: Offline-friendly testing suite that mocks Ollama and verifies streaming SSE and metrics responses.
* **`phases.md`**: Tracks progress checklist across all five development stages.
* **`interview_notes.md`**: Log of design justifications, files, and concept cheat-sheet.
* **`README.md`**: Standard documentation introducing layout, quickstart, and testing command pipelines.
* **`src/Dockerfile`**: Configured for multi-stage secure containerization. It uses a builder stage to compile requirements, creates a non-root group and user (UID/GID `10001`), copies files into local paths under the user's scope, and drops root permissions entirely before starting FastAPI.
* **`manifests/k3d-config.yaml`**: Multi-node topology config setting up 1 control plane and 2 worker agents. Maps specific NodePorts from the host to k3d nodes to enable direct developer access.
* **`scripts/bootstrap.sh`**: Extended bootstrap script that creates the cluster/registry, builds/registers the FastAPI image, imports all Docker images (ArgoCD, Qdrant, Ollama) offline, installs ArgoCD, and deploys the unified Helm chart.
* **`scripts/deploy_monitoring.sh`**: Automates deploying both `kube-prometheus-stack` and `loki-stack` in the `monitoring` namespace using local tarballs.
* **`manifests/charts/agentic-edge-stack/`**:
  * **`Chart.yaml`**: Standard Helm metadata file describing version, appVersion, and description.
  * **`values.yaml`**: Configures all parameters (e.g. image name/tags, ports, HPA cpu utilisation, persistent volumes sizes, and resource constraints) dynamically.
  * **`templates/`**:
    * **`agent-deployment.yaml` & `agent-service.yaml`**: Deploys the FastAPI service with liveness/readiness probes and maps ports to Host NodePort `30000`.
    * **`agent-configmap.yaml` & `agent-secret.yaml`**: Houses connection strings (pointing to `ollama-service` and `qdrant-service`) and the API bearer key.
    * **`agent-hpa.yaml`**: Configures HPA scaling boundaries (min 2, max 10, target 50% CPU).
    * **`ollama-statefulset.yaml` & `ollama-service.yaml` & `ollama-pvc.yaml`**: Stateful deployment of the Ollama server. Includes an automated model puller script (using `ollama list` loops) to download `qwen2.5:0.5b` to the 10Gi persistent volume.
    * **`ollama-configmap.yaml`**: Houses the custom `Modelfile` settings (temperature, context length, system prompt, prediction limits) used to compile our optimized model at startup.
    * **`qdrant-statefulset.yaml` & `qdrant-service.yaml` & `qdrant-pvc.yaml`**: Stateful deployment of the Qdrant database. Mounts a 5Gi persistent volume and exposes http/grpc ports.
    * **`agent-podmonitor.yaml`**: Configures the Prometheus `PodMonitor` target to scrape FastAPI metrics dynamically inside the cluster.
    * **`agent-dashboard-configmap.yaml`**: Houses the declarative custom MLOps Grafana dashboard definition mapping CPU, memory, request rates, latencies, and Loki logs.
* **`manifests/monitoring/`**:
  * **`prometheus-values.yaml`**: Local overrides for `kube-prometheus-stack`, pinning image repositories/tags and setting up Grafana NodePort 30030 with automatic Loki datasource provisioning.
  * **`loki-values.yaml`**: Local overrides config for Loki + Promtail to run offline in the cluster.
* **`gitops/application.yaml`**: ArgoCD Application manifest linking your repository path (`manifests/charts/agentic-edge-stack`) to the cluster, enabling GitOps synchronization.
* **`gitops/argocd-install.yaml`**: ArgoCD installation manifests (downloaded from the stable repository).



