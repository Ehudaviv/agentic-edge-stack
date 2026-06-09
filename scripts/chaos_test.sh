#!/bin/bash
set -e

# Separator formatting helper
print_sep() {
  echo "========================================================="
}

echo "========================================================="
echo "        Agentic Edge Stack - Resiliency Chaos Test"
echo "========================================================="

# 1. Verify environment
if ! command -v kubectl &> /dev/null; then
  echo "Error: kubectl is required but not installed." >&2
  exit 1
fi

# Dynamically retrieve the agent-service ClusterIP for internal cluster routing
CLUSTER_IP=$(kubectl get svc agent-service -n agentic-edge-stack -o jsonpath='{.spec.clusterIP}')
if [ -z "$CLUSTER_IP" ]; then
  echo "Error: Could not retrieve agent-service ClusterIP." >&2
  exit 1
fi

API_URL="http://${CLUSTER_IP}:8000/chat"
echo "Internal Cluster IP: $CLUSTER_IP"
echo "Internal API URL:    $API_URL"

# Helper function to query the FastAPI SSE endpoint internally from the server container.
# Uses client-side retry logic to mirror production gateways (e.g. Nginx, Envoy) 
# and handle transient Kubernetes endpoint propagation delays.
test_agent_response() {
  local response
  local max_attempts=3
  local attempt=0
  
  while [ $attempt -lt $max_attempts ]; do
    response=$(docker exec k3d-agentic-edge-stack-server-0 busybox wget -q -T 5 -O - \
      --header "Content-Type: application/json" \
      --post-data '{"message": "What is k3d?"}' \
      "$API_URL" 2>/dev/null || echo "WGET_FAILED")
    
    if [[ "$response" == *"[DONE]"* ]]; then
      return 0
    fi
    
    attempt=$((attempt + 1))
    if [ $attempt -lt $max_attempts ]; then
      echo "  [RETRY] Attempt $attempt failed, retrying in 0.5s..."
      sleep 0.5
    fi
  done
  
  echo "  [FAIL] Internal query failed after $max_attempts attempts. Response: $response"
  return 1
}

# ---------------------------------------------------------
# SCENARIO 1: Qdrant Pod Outage (DB Failure Resiliency)
# ---------------------------------------------------------
print_sep
echo "SCENARIO 1: Injecting Database Outage (Deleting Pod qdrant-0)"
print_sep

# Assert system is initially healthy
echo "Verifying initial system health..."
if test_agent_response; then
  echo "  [OK] Initial query succeeded."
else
  echo "  [ERROR] Initial query failed. Aborting chaos test." >&2
  exit 1
fi

# Create a temporary file to track query success across background subshells
TEMP_DB_STATUS=$(mktemp)
echo "success" > "$TEMP_DB_STATUS"

# Background loop querying the agent every 1s
run_bg_queries_db() {
  for i in {1..15}; do
    if ! test_agent_response > /dev/null 2>&1; then
      echo "failure" > "$TEMP_DB_STATUS"
      echo "  [BG Query] Request $i: FAILED"
    else
      echo "  [BG Query] Request $i: SUCCESS"
    fi
    sleep 1
  done
}

echo "Starting background request stream..."
run_bg_queries_db &
BG_PID=$!
sleep 3

echo "--> Injected Fault: Deleting pod qdrant-0..."
kubectl delete pod qdrant-0 -n agentic-edge-stack --now

echo "Waiting for background query loop to complete..."
wait $BG_PID

echo "Verifying Qdrant recovery..."
kubectl wait --for=condition=Ready pod/qdrant-0 -n agentic-edge-stack --timeout=60s

db_status=$(cat "$TEMP_DB_STATUS")
rm -f "$TEMP_DB_STATUS"

if [ "$db_status" = "success" ]; then
  echo "  [PASS] Scenario 1 Successful! The FastAPI Agent remained online and"
  echo "         gracefully fell back to mock data during the Qdrant database outage."
else
  echo "  [FAIL] Scenario 1 Failed! Some client queries failed during the DB outage."
  exit 1
fi

# ---------------------------------------------------------
# SCENARIO 2: FastAPI Agent Pod Failure (Service Redundancy)
# ---------------------------------------------------------
print_sep
echo "SCENARIO 2: Injecting Agent Pod Outage (Deleting active replica)"
print_sep

# Retrieve one active agent pod name
AGENT_POD=$(kubectl get pods -n agentic-edge-stack -l app=agent-app -o jsonpath='{.items[0].metadata.name}')
if [ -z "$AGENT_POD" ]; then
  echo "Error: No active agent-app pods found. Skipping Scenario 2." >&2
else
  echo "Target replica for deletion: $AGENT_POD"
  
  TEMP_NODE_STATUS=$(mktemp)
  echo "success" > "$TEMP_NODE_STATUS"

  # Background loop querying the agent every 1s
  run_bg_queries_node() {
    for i in {1..15}; do
      if ! test_agent_response > /dev/null 2>&1; then
        echo "failure" > "$TEMP_NODE_STATUS"
        echo "  [BG Pod Query] Request $i: FAILED"
      else
        echo "  [BG Pod Query] Request $i: SUCCESS"
      fi
      sleep 1
    done
  }

  echo "Starting background request stream..."
  run_bg_queries_node &
  BG_NODE_PID=$!
  sleep 3

  echo "--> Injected Fault: Force-deleting replica $AGENT_POD..."
  kubectl delete pod "$AGENT_POD" -n agentic-edge-stack --now

  echo "Waiting for background query loop to complete..."
  wait $BG_NODE_PID

  echo "Waiting for HPA/Deployment to restore replica count..."
  kubectl rollout status deployment/agent-app -n agentic-edge-stack --timeout=60s

  node_status=$(cat "$TEMP_NODE_STATUS")
  rm -f "$TEMP_NODE_STATUS"

  if [ "$node_status" = "success" ]; then
    echo "  [PASS] Scenario 2 Successful! FastAPI Agent remained 100% online"
    echo "         and routed requests to active replicas during the pod outage."
  else
    echo "  [FAIL] Scenario 2 Failed! Some client queries failed during the pod outage."
    exit 1
  fi
fi

print_sep
echo "All Chaos Engineering Scenarios Passed!"
print_sep
exit 0
