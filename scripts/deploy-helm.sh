#!/usr/bin/env bash
set -euo pipefail

RELEASE_NAME="${RELEASE_NAME:-observability}"
NAMESPACE="${NAMESPACE:-observability}"
VALUES_FILE="${VALUES_FILE:-helm/observability-stack/values-gke.yaml}"
CHART="helm/observability-stack"

echo "Using kube context: $(kubectl config current-context)"

EXTRA=()
if [[ "${INTERNAL:-false}" == "true" ]]; then
  EXTRA+=(-f helm/observability-stack/values-internal.yaml)
fi

if [[ "${DRY_RUN:-false}" == "true" ]]; then
  helm upgrade --install "$RELEASE_NAME" "$CHART" \
    -n "$NAMESPACE" --create-namespace \
    -f "$VALUES_FILE" "${EXTRA[@]}" --dry-run --debug
  exit 0
fi

helm upgrade --install "$RELEASE_NAME" "$CHART" \
  -n "$NAMESPACE" --create-namespace \
  -f "$VALUES_FILE" "${EXTRA[@]}"

kubectl rollout status deployment -n "$NAMESPACE" -l app.kubernetes.io/component=grafana --timeout=180s
kubectl rollout status statefulset -n "$NAMESPACE" -l app.kubernetes.io/component=prometheus --timeout=180s
kubectl rollout status daemonset -n "$NAMESPACE" -l app.kubernetes.io/component=node-exporter --timeout=180s
helm test "$RELEASE_NAME" -n "$NAMESPACE"
