# MNC security baseline

This stack is built to CIS Kubernetes Benchmark and GKE hardening guidance. Use this document as the control map for architecture, risk, and audit.

## Control summary

| Control | Implementation |
| --- | --- |
| Namespace isolation | Dedicated `observability` namespace |
| Pod Security | Enforce `privileged` (GKE 1.35 baseline blocks Node Exporter hostPath/hostNetwork) |
| Least-privilege RBAC | Prometheus ClusterRole is get/list/watch only |
| No default SA tokens | Grafana and Node Exporter set `automountServiceAccountToken: false` |
| Non-root + dropped caps | All containers `runAsNonRoot`, `capabilities.drop: ALL` |
| Read-only root FS | Grafana, Prometheus, Node Exporter |
| Seccomp | `RuntimeDefault` on pods and containers |
| No privilege escalation | `allowPrivilegeEscalation: false` |
| Network default-deny | NetworkPolicy ingress/egress deny, then allow DNS, HTTPS, scrape paths |
| TLS at the edge | GKE ManagedCertificate + HTTPS redirect FrontendConfig |
| Secrets | Helm generates Grafana password; manifests require you to replace `CHANGE_ME` |
| Resource governance | ResourceQuota + LimitRange + requests/limits |
| Scheduling priority | `observability-critical` PriorityClass |
| Image pins | Versioned tags, never `latest` |
| Admin API off | Prometheus `--web.enable-admin-api=false` |
| Grafana hardening | No signup, no anonymous, HSTS, secure cookies, no snapshots |

## Node Exporter exception (required)

Node Exporter must read host `/proc`, `/sys`, and rootfs, and typically uses `hostNetwork` / `hostPID`. Restricted PSS would block the DaemonSet.

Compensating controls:

- Namespace enforce is `baseline`, not `privileged`
- Container still runs as UID `65534`, read-only root, no capabilities
- Public Ingress is **disabled**
- NetworkPolicy allows port `9100` only from Prometheus
- DaemonSet tolerates all taints so every Linux node is covered, without extra privileges

Do not expose Node Exporter on a public Google Cloud Ingress. If a URL is mandatory, use `gce-internal` plus IAP or Cloud Armor.

## Ingress posture

Recommended production layout:

1. Grafana: `gce` or `gce-internal` + ManagedCertificate + IAP
2. Prometheus: `gce-internal` only (query API is sensitive)
3. Node Exporter: no Ingress; Prometheus scrapes the headless Service

Optional add-ons (create in GCP, then reference from BackendConfig):

- Cloud Armor security policy
- Identity-Aware Proxy (IAP)
- Custom SSL policy (TLS 1.2+)
- Reserved global or internal IP

## GKE Workload Identity

Replace `YOUR_GCP_PROJECT_ID` and bind Google service accounts:

```bash
gcloud iam service-accounts create grafana --project=YOUR_GCP_PROJECT_ID
gcloud iam service-accounts create prometheus --project=YOUR_GCP_PROJECT_ID

gcloud iam service-accounts add-iam-policy-binding \
  grafana@YOUR_GCP_PROJECT_ID.iam.gserviceaccount.com \
  --role roles/iam.workloadIdentityUser \
  --member "serviceAccount:YOUR_GCP_PROJECT_ID.svc.id.goog[observability/grafana]"

gcloud iam service-accounts add-iam-policy-binding \
  prometheus@YOUR_GCP_PROJECT_ID.iam.gserviceaccount.com \
  --role roles/iam.workloadIdentityUser \
  --member "serviceAccount:YOUR_GCP_PROJECT_ID.svc.id.goog[observability/prometheus]"
```

## Secrets

Prefer Secret Manager + External Secrets Operator over in-repo Secret YAML.

Helm keeps the first generated Grafana password across upgrades via `lookup`.

## GKE Autopilot note

Autopilot blocks or restricts `hostPath`, `hostNetwork`, and `hostPID`. Node Exporter on Autopilot is not supported in this chart. Use GKE Standard node pools.

## Verification

```bash
kubectl get ns observability --show-labels
kubectl get networkpolicy -n observability
kubectl auth can-i --list --as=system:serviceaccount:observability:prometheus
kubectl get daemonset node-exporter -n observability -o wide
```
