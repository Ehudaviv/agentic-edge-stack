#!/bin/bash
set -eo pipefail

echo "========================================================="
echo "       Installing Observability Stack (Prometheus & Loki)"
echo "========================================================="

# 1. Create namespace
echo "Creating monitoring namespace..."
kubectl create namespace monitoring || true

# 2. Deploy kube-prometheus-stack
echo "Installing/Upgrading kube-prometheus-stack from local tarball..."
helm upgrade --install prometheus manifests/monitoring/kube-prometheus-stack-86.2.0.tgz \
  -n monitoring \
  --create-namespace \
  -f manifests/monitoring/prometheus-values.yaml

# 3. Deploy loki-stack
echo "Installing/Upgrading loki-stack from local tarball..."
helm upgrade --install loki-stack manifests/monitoring/loki-stack-2.10.3.tgz \
  -n monitoring \
  --create-namespace \
  -f manifests/monitoring/loki-values.yaml

echo "========================================================="
echo "Observability Stack Installation Completed!"
echo "Access point:"
echo "- Grafana Dashboard: http://localhost:30030"
echo "  Username: admin"
echo "  Password: admin"
echo "========================================================="
