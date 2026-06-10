#!/bin/bash
set -eo pipefail

# Namespaces to monitor
NAMESPACES=("agentic-edge-stack" "monitoring" "argocd")

echo "========================================================="
echo "       Waiting for Cluster Components Readiness"
echo "========================================================="

wait_for_namespace() {
  local ns=$1
  echo "Waiting for namespace '$ns' to be created..."
  
  # Wait up to 60 iterations (120 seconds / 2 minutes)
  for i in {1..60}; do
    if kubectl get ns "$ns" &>/dev/null; then
      echo "  [OK] Namespace '$ns' exists."
      return 0
    fi
    sleep 2
  done
  
  echo "  [ERROR] Timeout waiting for namespace '$ns' to be created."
  return 1
}

wait_for_pods() {
  local ns=$1
  echo "Checking pod readiness in namespace '$ns'..."
  
  # Wait up to 45 iterations (450 seconds / ~7.5 minutes)
  for i in {1..45}; do
    # This go-template check identifies any pod that:
    # 1. Is not Succeeded (Completed Job)
    # 2. Is not Failed
    # 3. Either has no container status yet, OR has at least one container that is not ready.
    local unready
    unready=$(kubectl get pods -n "$ns" -o go-template='{{range .items}}{{if not (or (eq .status.phase "Succeeded") (eq .status.phase "Failed"))}}{{if .status.containerStatuses}}{{range .status.containerStatuses}}{{if not .ready}}unready {{end}}{{end}}{{else}}unready {{end}}{{end}}{{end}}' 2>/dev/null)
    
    if [ -z "$unready" ]; then
      echo "  [OK] All active pods in '$ns' namespace are ready!"
      return 0
    fi
    
    echo "  [WAIT] Some pods in '$ns' are still initializing (Attempt $i/45)..."
    sleep 10
  done
  
  echo "  [ERROR] Timeout waiting for pods in '$ns' to be ready."
  return 1
}

for ns in "${NAMESPACES[@]}"; do
  if ! wait_for_namespace "$ns"; then
    exit 1
  fi
  if ! wait_for_pods "$ns"; then
    exit 1
  fi
done

echo "========================================================="
echo "   All cluster namespaces are online and fully healthy!"
echo "========================================================="
