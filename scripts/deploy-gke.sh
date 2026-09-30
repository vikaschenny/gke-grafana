#!/usr/bin/env bash
# One-command GKE deploy. No file edits required.
# Prerequisite: kubectl is logged into a GKE Standard cluster.
#   gcloud container clusters get-credentials CLUSTER --region REGION --project PROJECT
#
# Usage:
#   ./scripts/deploy-gke.sh
#   DRY_RUN=true ./scripts/deploy-gke.sh
#   NAMESPACE=observability ./scripts/deploy-gke.sh

set -euo pipefail

NAMESPACE="${NAMESPACE:-observability}"
DRY_RUN="${DRY_RUN:-false}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
MANIFEST_DIR="${REPO_ROOT}/manifests"
cd "${REPO_ROOT}"

if ! command -v kubectl >/dev/null 2>&1; then
  echo "kubectl is not installed or not on PATH." >&2
  exit 1
fi

CONTEXT="$(kubectl config current-context 2>/dev/null || true)"
if [[ -z "${CONTEXT}" ]]; then
  echo "No kubectl context. Run: gcloud container clusters get-credentials <CLUSTER> --region <REGION> --project <PROJECT>" >&2
  exit 1
fi

echo "Deploying to kube context: ${CONTEXT}"
if ! kubectl cluster-info --request-timeout=15s >/dev/null; then
  echo "Cannot reach the cluster. Check VPN, credentials, and context." >&2
  exit 1
fi

if kubectl get nodes -o yaml 2>/dev/null | grep -q "autopilot.gke.io"; then
  echo "WARNING: Autopilot detected. Node Exporter may not schedule (hostPath/hostNetwork blocked)."
fi

if [[ "${DRY_RUN}" == "true" ]]; then
  kubectl apply -k "${MANIFEST_DIR}" --dry-run=client
  echo "Dry-run complete."
  exit 0
fi

kubectl apply -f "${MANIFEST_DIR}/00-namespace.yaml"

if ! kubectl get secret grafana-admin -n "${NAMESPACE}" >/dev/null 2>&1; then
  if command -v openssl >/dev/null 2>&1; then
    PASSWORD="$(openssl rand -base64 24 | tr -d '/+=' | head -c 24)"
  else
    PASSWORD="$(LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c 24)"
  fi
  kubectl create secret generic grafana-admin \
    -n "${NAMESPACE}" \
    --from-literal=admin-user=admin \
    --from-literal=admin-password="${PASSWORD}"
  echo "Created grafana-admin secret."
fi

# Drop leftover example.com TLS objects from earlier revisions so HTTP Ingress can go public.
kubectl delete managedcertificate grafana-cert prometheus-cert -n "${NAMESPACE}" --ignore-not-found >/dev/null
kubectl delete frontendconfig grafana-frontend prometheus-frontend -n "${NAMESPACE}" --ignore-not-found >/dev/null
kubectl delete ingress prometheus -n "${NAMESPACE}" --ignore-not-found >/dev/null

kubectl apply -k "${MANIFEST_DIR}"

echo "Waiting for rollouts..."
kubectl rollout status deployment/grafana -n "${NAMESPACE}" --timeout=300s
kubectl rollout status statefulset/prometheus -n "${NAMESPACE}" --timeout=300s
kubectl rollout status daemonset/node-exporter -n "${NAMESPACE}" --timeout=300s

echo
echo "Waiting for public Grafana Ingress IP (GKE load balancer can take 5-10 minutes)..."
INGRESS_IP=""
for _ in $(seq 1 60); do
  INGRESS_IP="$(kubectl get ingress grafana -n "${NAMESPACE}" -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)"
  if [[ -n "${INGRESS_IP}" ]]; then
    break
  fi
  sleep 10
done

echo
echo "Deployed. Resources in namespace ${NAMESPACE}:"
kubectl get pods,svc,ingress,daemonset -n "${NAMESPACE}"

PASSWORD="$(kubectl get secret grafana-admin -n "${NAMESPACE}" -o jsonpath='{.data.admin-password}' | base64 --decode 2>/dev/null || kubectl get secret grafana-admin -n "${NAMESPACE}" -o jsonpath='{.data.admin-password}' | base64 -d)"
echo
echo "Grafana user: admin"
echo "Grafana password: ${PASSWORD}"

if [[ -n "${INGRESS_IP}" ]]; then
  echo
  echo "Public Grafana URL: http://${INGRESS_IP}"
else
  echo
  echo "Ingress IP is still provisioning. Check with:"
  echo "  kubectl get ingress grafana -n ${NAMESPACE}"
  echo "Then open http://<ADDRESS>"
fi

echo
echo "Prometheus stays cluster-internal:"
echo "  kubectl -n ${NAMESPACE} port-forward svc/prometheus 9090:9090"
