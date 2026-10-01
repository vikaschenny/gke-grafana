#!/usr/bin/env bash
# Apply only the Prometheus + namespace fixes, then recreate the crashing pod.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
NS="${NAMESPACE:-observability}"

kubectl apply -f "${REPO_ROOT}/manifests/00-namespace.yaml"
kubectl apply -f "${REPO_ROOT}/manifests/prometheus/configmap.yaml"
kubectl apply -f "${REPO_ROOT}/manifests/prometheus/statefulset.yaml"
kubectl apply -f "${REPO_ROOT}/manifests/node-exporter/daemonset.yaml"

echo "Recreating prometheus-0 so the new spec is used..."
kubectl delete pod prometheus-0 -n "${NS}" --ignore-not-found --wait=false

echo "Waiting for prometheus-0..."
kubectl rollout status statefulset/prometheus -n "${NS}" --timeout=300s

echo
echo "--- init chmod ---"
kubectl logs prometheus-0 -n "${NS}" -c init-chmod-data --tail=50 || true
echo "--- prometheus ---"
kubectl logs prometheus-0 -n "${NS}" -c prometheus --tail=80 || true

kubectl get pods -n "${NS}"
