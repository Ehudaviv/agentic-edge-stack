#!/bin/bash
set -eo pipefail

echo "========================================================="
echo "       Observability Stack is managed by ArgoCD"
echo "========================================================="

kubectl apply -f gitops/application.yaml
