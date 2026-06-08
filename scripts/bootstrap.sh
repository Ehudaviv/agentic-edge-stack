#!/bin/bash
set -eo pipefail

CLUSTER_NAME="agentic-edge-stack"
REGISTRY_NAME="registry.localhost"
REGISTRY_PORT="5001"
IMAGE_TAG="localhost:${REGISTRY_PORT}/agent-app:latest"

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

# 2. Cleanup existing cluster if any
echo "Cleaning up any existing cluster named '$CLUSTER_NAME'..."
k3d cluster delete "$CLUSTER_NAME" || true
k3d registry delete "$REGISTRY_NAME" || true

# 3. Create the cluster and registry
echo "Creating k3d registry..."
k3d registry create "$REGISTRY_NAME" --port "$REGISTRY_PORT" || true

echo "Creating k3d cluster..."
k3d cluster create --config manifests/k3d-config.yaml

echo "Waiting for cluster to be ready..."
kubectl wait --for=condition=Ready nodes --all --timeout=60s

echo "Cluster and registry created successfully!"
kubectl cluster-info

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

# 6. Import offline cached images into the k3d cluster to enable offline operation
echo "Importing offline cached images into k3d..."
k3d image import \
  quay.io/argoproj/argocd:v3.4.3 \
  ghcr.io/dexidp/dex:v2.45.0 \
  public.ecr.aws/docker/library/redis:8.2.3-alpine \
  ollama/ollama:latest \
  qdrant/qdrant:latest \
  -c "$CLUSTER_NAME"

# 7. Install ArgoCD in the cluster
echo "Deploying ArgoCD..."
kubectl create namespace argocd || true
kubectl apply -n argocd -f gitops/argocd-install.yaml --server-side --force-conflicts

echo "Patching ArgoCD server to NodePort 30080..."
kubectl patch svc argocd-server -n argocd -p '{"spec": {"type": "NodePort", "ports": [{"port": 80, "targetPort": 8080, "nodePort": 30080, "name": "http"}, {"port": 443, "targetPort": 8080, "nodePort": 30443, "name": "https"}]}}'

# 8. Deploy the Agentic Edge Stack Helm Chart
echo "Creating application namespace 'agentic-edge-stack'..."
kubectl create namespace agentic-edge-stack || true

echo "Installing/Upgrading Agentic Edge Stack Helm Chart..."
helm upgrade --install agentic-edge-stack manifests/charts/agentic-edge-stack -n agentic-edge-stack

echo "========================================================="
echo "Bootstrap Complete! The Agentic Edge Stack is deployed."
echo "Access points:"
echo "- FastAPI Agent App: http://localhost:30000"
echo "- Ollama Inference:  http://localhost:30134"
echo "- Qdrant Vector DB:  http://localhost:30333"
echo "- ArgoCD GitOps UI:  http://localhost:30080"
echo "========================================================="

