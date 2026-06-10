#!/bin/bash
set -eo pipefail

CLUSTER_NAME="agentic-edge-stack"
REGISTRY_NAME="registry.localhost"
REGISTRY_PORT="5001"
IMAGE_TAG="localhost:${REGISTRY_PORT}/agent-app:latest"

# Set up a temporary DOCKER_CONFIG directory to bypass host credential helper failures
# when pushing to the local unauthenticated registry.
export DOCKER_CONFIG="$(mktemp -d)"
trap 'rm -rf "$DOCKER_CONFIG"' EXIT

echo "========================================================="
echo "        Bootstrapping The Agentic Edge Stack"
echo "========================================================="

# Helper to check command availability
check_cmd() {
  if ! command -v "$1" &> /dev/null; then
    echo "Error: $1 is required but not installed." >&2
    exit 1
  fi
}

# 1. Check prerequisites
echo "Checking prerequisites..."
check_cmd docker
check_cmd k3d
check_cmd kubectl
check_cmd helm

# Detect INFRA_ONLY mode and fallback if cluster is missing
if [ "$INFRA_ONLY" = "true" ]; then
  if ! k3d cluster list "$CLUSTER_NAME" &>/dev/null; then
    echo "Warning: Cluster '$CLUSTER_NAME' does not exist. Disabling INFRA_ONLY mode."
    INFRA_ONLY="false"
  else
    echo "INFRA_ONLY=true: Reusing existing cluster and registry."
  fi
fi

if [ "$INFRA_ONLY" != "true" ]; then
  # 2. Cleanup existing cluster if any
  echo "Cleaning up any existing cluster named '$CLUSTER_NAME'..."
  k3d cluster delete "$CLUSTER_NAME" || true

  # 3. Create the cluster and registry
  echo "Creating k3d registry..."
  k3d registry create "$REGISTRY_NAME" --port "$REGISTRY_PORT" || true

  echo "Creating k3d cluster..."
  k3d cluster create --config manifests/k3d-config.yaml

  echo "Waiting for cluster to be ready..."
  kubectl wait --for=condition=Ready nodes --all --timeout=60s

  echo "Cluster and registry created successfully!"
  kubectl cluster-info
fi

# 4. Build and containerize the FastAPI Agent service
echo "Building the FastAPI Agent production Docker image..."
docker build -t "$IMAGE_TAG" -f src/Dockerfile src/

# 5. Push the image to the local registry
echo "Pushing the FastAPI Agent image to the local registry..."
# Retry logic in case the registry container is still warming up
max_retries=5
count=0
until docker push "$IMAGE_TAG" || [ $count -eq $max_retries ]; do
  echo "Push failed, retrying in 2 seconds..."
  sleep 2
  count=$((count + 1))
done

if [ $count -eq $max_retries ]; then
  echo "Error: Failed to push image to local registry after $max_retries attempts." >&2
  exit 1
fi

if [ "$INFRA_ONLY" != "true" ]; then
  # 6. Import offline cached images into the k3d cluster to enable offline operation
  echo "Checking and pulling offline images if needed..."
  IMAGES_TO_IMPORT=(
    # ArgoCD & Stack Core
    "quay.io/argoproj/argocd:v3.4.3"
    "ghcr.io/dexidp/dex:v2.45.0"
    "public.ecr.aws/docker/library/redis:8.2.3-alpine"
    "ollama/ollama:latest"
    "qdrant/qdrant:latest"
    
    # Monitoring (Prometheus & Loki Stacks)
    "quay.io/prometheus-operator/prometheus-operator:v0.91.0"
    "quay.io/prometheus-operator/prometheus-config-reloader:v0.91.0"
    "quay.io/prometheus/prometheus:v3.12.0-distroless"
    "quay.io/prometheus/alertmanager:v0.32.2"
    "quay.io/prometheus/node-exporter:v1.11.1-distroless"
    "registry.k8s.io/kube-state-metrics/kube-state-metrics:v2.19.0"
    "grafana/grafana:13.0.1-security-01"
    "quay.io/kiwigrid/k8s-sidecar:2.7.3"
    "grafana/loki:2.6.1"
    "grafana/promtail:3.5.1"
    "docker.io/busybox:1.33"
  )

  # Detect host architecture to ensure platform compatibility (AMD64 vs ARM64)
  ARCH=$(uname -m)
  if [ "$ARCH" = "x86_64" ]; then
    PLATFORM="linux/amd64"
  elif [ "$ARCH" = "aarch64" ] || [ "$ARCH" = "arm64" ]; then
    PLATFORM="linux/arm64"
  else
    PLATFORM="linux/amd64"
  fi

  for img in "${IMAGES_TO_IMPORT[@]}"; do
    if ! docker image inspect "$img" >/dev/null 2>&1; then
      echo "Image $img not found locally on host. Pulling..."
      docker pull --platform "$PLATFORM" "$img"
    fi
  done

  echo "Tagging and pushing offline images to local registry..."
  for img in "${IMAGES_TO_IMPORT[@]}"; do
    local_tag="localhost:5001/${img}"
    echo "  Re-packaging and pushing $img to local registry..."
    echo "FROM $img" | docker build --platform "$PLATFORM" -t "$local_tag" -
    docker push "$local_tag"
  done
fi


# 7. Install ArgoCD in the cluster
echo "Deploying ArgoCD..."
kubectl create namespace argocd || true
sed -e 's|quay.io/argoproj/argocd:|k3d-registry.localhost:5001/quay.io/argoproj/argocd:|g' \
    -e 's|ghcr.io/dexidp/dex:|k3d-registry.localhost:5001/ghcr.io/dexidp/dex:|g' \
    -e 's|public.ecr.aws/docker/library/redis:|k3d-registry.localhost:5001/public.ecr.aws/docker/library/redis:|g' \
    gitops/argocd-install.yaml | kubectl apply -n argocd -f - --server-side --force-conflicts

echo "Patching ArgoCD server to NodePort 30080..."
kubectl patch svc argocd-server -n argocd -p '{"spec": {"type": "NodePort", "ports": [{"port": 80, "targetPort": 8080, "nodePort": 30080, "name": "http"}, {"port": 443, "targetPort": 8080, "nodePort": 30443, "name": "https"}]}}'

# 8. Deploy the Agentic Edge Stack via GitOps (ArgoCD)
echo "Deploying the Agentic Edge Stack Application via ArgoCD..."
kubectl apply -f gitops/application.yaml

echo "========================================================="
echo "Bootstrap Complete! The Agentic Edge Stack is deployed."
echo "Access points:"
echo "- FastAPI Agent App: http://localhost:30000"
echo "- Ollama Inference:  http://localhost:30134"
echo "- Qdrant Vector DB:  http://localhost:30333"
echo "- ArgoCD GitOps UI:  http://localhost:30080"
echo "========================================================="

