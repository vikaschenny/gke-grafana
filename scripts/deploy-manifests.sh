#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="${NAMESPACE:-observability}"
MANIFEST_DIR="manifests"

echo "Using kube context: $(kubectl config current-context)"

if [[ "${DRY_RUN:-false}" == "true" ]]; then
  kubectl apply -k "$MANIFEST_DIR" --dry-run=client
  exit 0
fi

kubectl apply -f "$MANIFEST_DIR/00-namespace.yaml"

if ! kubectl get secret grafana-admin -n "$NAMESPACE" >/dev/null 2>&1; then
  PASSWORD="$(openssl rand -base64 24 | tr -d '/+=' | head -c 24)"
  kubectl create secret generic grafana-admin \
    -n "$NAMESPACE" \
    --from-literal=admin-user=admin \
    --from-literal=admin-password="$PASSWORD"
  echo "Grafana admin password is in secret grafana-admin"
fi

kubectl apply -k "$MANIFEST_DIR"
kubectl rollout status deployment/grafana -n "$NAMESPACE" --timeout=180s
kubectl rollout status statefulset/prometheus -n "$NAMESPACE" --timeout=180s
kubectl rollout status daemonset/node-exporter -n "$NAMESPACE" --timeout=180s
kubectl get pods,svc,ingress,daemonset -n "$NAMESPACE"
