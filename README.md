# GKE observability stack

Production Helm chart **and** raw Kubernetes manifests for **Grafana**, **Prometheus**, and **Node Exporter** on Google Kubernetes Engine (GKE Standard).

The stack includes Ingress (TLS), a Node Exporter DaemonSet on every Linux node, and MNC-oriented security: Pod Security, NetworkPolicy default-deny, least-privilege RBAC, non-root containers, resource quotas, and pinned images.

```
                    HTTPS (GKE Ingress + ManagedCertificate)
                    /                    \
           grafana.example.com    prometheus.example.com
                    |                    |
                 Grafana  --------->  Prometheus
                                         |
                              scrape (cluster-internal)
                                         |
                              Node Exporter DaemonSet
                              (one pod on every Linux node)
```

## What you get

| Component | Workload | Exposure |
| --- | --- | --- |
| Grafana 11.4.0 | Deployment + PVC | Ingress + TLS |
| Prometheus 2.55.1 | StatefulSet + PVC | Ingress + TLS |
| Node Exporter 1.8.2 | DaemonSet (all Linux nodes) | ClusterIP only (Ingress off) |

Node Exporter Ingress is **disabled on purpose**. Host metrics must not be internet-facing. Prometheus scrapes `node-exporter.observability.svc:9100`. An optional internal Ingress snippet is in the chart and in `manifests/node-exporter/ingress.yaml`.

## Deploy now (no file edits)

Point `kubectl` at a **GKE Standard** cluster, then run:

```bash
gcloud container clusters get-credentials CLUSTER --region REGION --project PROJECT
chmod +x scripts/deploy-gke.sh
./scripts/deploy-gke.sh
```

Windows PowerShell:

```powershell
gcloud container clusters get-credentials CLUSTER --region REGION --project PROJECT
.\scripts\deploy-gke.ps1
```

The script creates the namespace, generates a Grafana password, applies manifests, and waits for the public Ingress IP.

**Public Grafana** (no DNS required):

```powershell
kubectl get ingress grafana -n observability
```

Open `http://<ADDRESS>` — user `admin`; password is printed by the script. GKE can take 5–10 minutes to assign the IP.

Prometheus stays internal:

```powershell
kubectl -n observability port-forward svc/prometheus 9090:9090
```

## Prerequisites

- GKE **Standard** cluster (Autopilot blocks hostPath / hostNetwork used by Node Exporter)
- Kubernetes 1.28+
- `kubectl` pointed at the cluster
- Helm 3.14+ (Helm path only)
- DNS records for Grafana and Prometheus pointing at the Ingress IP (only if you want public URLs)
- Workload Identity is optional; not required for this stack to start

Reserve static IPs (optional):

```bash
gcloud compute addresses create grafana-ip --global
gcloud compute addresses create prometheus-ip --global
```

## Option 1 — Helm (recommended)

1. Edit `helm/observability-stack/values-gke.yaml`:
   - `global.gcpProjectId`
   - `grafana.ingress.host`
   - `prometheus.ingress.host`
   - Workload Identity annotations
2. Install:

```powershell
.\scripts\deploy-helm.ps1
```

Or:

```bash
helm upgrade --install observability helm/observability-stack \
  -n observability --create-namespace \
  -f helm/observability-stack/values-gke.yaml
```

Private (internal) Ingress:

```powershell
.\scripts\deploy-helm.ps1 -Internal
```

```bash
INTERNAL=true ./scripts/deploy-helm.sh
```

Dry-run:

```powershell
.\scripts\deploy-helm.ps1 -DryRun
```

Get the Grafana password:

```bash
kubectl get secret -n observability -l app.kubernetes.io/component=grafana \
  -o jsonpath='{.items[0].data.admin-password}' | base64 -d
```

## Option 2 — Kubernetes manifests (Kustomize)

1. Replace `grafana.example.com` and `prometheus.example.com` in:
   - `manifests/grafana/ingress.yaml`
   - `manifests/grafana/configmap.yaml` (`root_url`)
   - `manifests/prometheus/ingress.yaml`
   - `manifests/overlays/gke-prod/kustomization.yaml`
2. Replace `YOUR_GCP_PROJECT_ID` in the Grafana and Prometheus ServiceAccounts.
3. Create the Grafana admin secret (Kustomize does not apply a password file):

```bash
kubectl apply -f manifests/00-namespace.yaml
kubectl create secret generic grafana-admin -n observability \
  --from-literal=admin-user=admin \
  --from-literal=admin-password="$(openssl rand -base64 24)"
```

`manifests/grafana/secret.yaml` is an example only. Do not commit a real password.
4. Apply:

```powershell
.\scripts\deploy-manifests.ps1
```

Or:

```bash
kubectl apply -k manifests
```

Overlay with custom hosts:

```bash
kubectl apply -k manifests/overlays/gke-prod
```

## After deploy

```bash
kubectl get pods,svc,ingress,daemonset -n observability
kubectl get managedcertificate -n observability
```

Wait until ManagedCertificate status is `Active`, then point DNS A records at the Ingress addresses:

```bash
kubectl get ingress -n observability
```

Open:

- `https://grafana.example.com` — Prometheus is already provisioned as the default datasource
- `https://prometheus.example.com` — targets should show `node-exporter` up on every node

## Security standards included

See [docs/SECURITY.md](docs/SECURITY.md) for the full control map.

- Isolated `observability` namespace
- Pod Security: enforce **baseline**, warn/audit **restricted**
- NetworkPolicy default-deny; Grafana → Prometheus → Node Exporter only
- Non-root, read-only root filesystem, drop ALL capabilities, RuntimeDefault seccomp
- Grafana: no signup, no anonymous, HSTS, secure cookies
- Prometheus: admin API disabled; read-only RBAC
- Node Exporter: documented host-access exception; no public Ingress
- ResourceQuota, LimitRange, PriorityClass, pinned image tags
- GKE NEG + BackendConfig health checks + HTTPS redirect

## Enable Node Exporter Ingress (not recommended)

Only if a corporate standard requires a URL. Use an **internal** load balancer.

Helm (`values-gke.yaml`):

```yaml
nodeExporter:
  ingress:
    enabled: true
    className: gce-internal
    host: node-exporter.internal.example.com
  managedCertificate:
    enabled: true
```

Then attach IAP or Cloud Armor.

## Common customizations

| Need | Where |
| --- | --- |
| Storage size / class | `grafana.persistence`, `prometheus.persistence`, or PVC YAML |
| Retention | `prometheus.retention` / `retentionSize` |
| Image registry / pull secrets | `global.imageRegistry`, `global.imagePullSecrets` |
| Cloud Armor | `*.backendConfig.securityPolicy` |
| Static IP | `ingress.staticIpName` or Ingress annotation |
| Skip a component | `grafana.enabled` / `prometheus.enabled` / `nodeExporter.enabled` |

## Uninstall

```bash
helm uninstall observability -n observability
kubectl delete pvc -n observability --all
```

Manifests:

```bash
kubectl delete -k manifests
```

ClusterRoles (`prometheus`) are cluster-scoped and must be deleted if you remove the namespace only.
