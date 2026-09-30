# One-command GKE deploy. No file edits required.
# Prerequisite: kubectl is logged into a GKE Standard cluster.
#   gcloud container clusters get-credentials CLUSTER --region REGION --project PROJECT

param(
    [string]$Namespace = "observability",
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Parent $PSScriptRoot
$ManifestDir = Join-Path $RepoRoot "manifests"
Set-Location $RepoRoot

function Assert-Command($name) {
    if (-not (Get-Command $name -ErrorAction SilentlyContinue)) {
        throw "$name is not installed or not on PATH."
    }
}

Assert-Command kubectl

$context = kubectl config current-context
if (-not $context) {
    throw "No kubectl context. Run: gcloud container clusters get-credentials <CLUSTER> --region <REGION> --project <PROJECT>"
}

Write-Host "Deploying to kube context: $context"
kubectl cluster-info --request-timeout=15s | Out-Null
if ($LASTEXITCODE -ne 0) {
    throw "Cannot reach the cluster. Check VPN, credentials, and context."
}

$autopilot = kubectl get nodes -o jsonpath="{.items[0].metadata.labels['autopilot\.gke\.io/']}" 2>$null
$nodePool = kubectl get nodes -o jsonpath="{.items[0].metadata.labels['cloud\.google\.com/gke-nodepool']}" 2>$null
if ($autopilot -or ($nodePool -eq "default-pool" -and (kubectl get nodes -o yaml | Select-String -Quiet "autopilot.gke.io"))) {
    Write-Host "WARNING: Autopilot detected. Node Exporter may not schedule (hostPath/hostNetwork blocked)."
}

if ($DryRun) {
    kubectl apply -k $ManifestDir --dry-run=client
    Write-Host "Dry-run complete."
    exit 0
}

kubectl apply -f (Join-Path $ManifestDir "00-namespace.yaml")

$existing = kubectl get secret grafana-admin -n $Namespace --ignore-not-found
if (-not $existing) {
    $password = -join ((48..57) + (65..90) + (97..122) | Get-Random -Count 24 | ForEach-Object { [char]$_ })
    kubectl create secret generic grafana-admin `
        -n $Namespace `
        --from-literal=admin-user=admin `
        --from-literal=admin-password=$password | Out-Null
    Write-Host "Created grafana-admin secret."
}

# Drop leftover example.com TLS objects from earlier revisions so HTTP Ingress can go public.
kubectl delete managedcertificate grafana-cert prometheus-cert -n $Namespace --ignore-not-found | Out-Null
kubectl delete frontendconfig grafana-frontend prometheus-frontend -n $Namespace --ignore-not-found | Out-Null
kubectl delete ingress prometheus -n $Namespace --ignore-not-found | Out-Null

kubectl apply -k $ManifestDir

Write-Host "Waiting for rollouts..."
kubectl rollout status deployment/grafana -n $Namespace --timeout=300s
kubectl rollout status statefulset/prometheus -n $Namespace --timeout=300s
kubectl rollout status daemonset/node-exporter -n $Namespace --timeout=300s

Write-Host ""
Write-Host "Waiting for public Grafana Ingress IP (GKE load balancer can take 5-10 minutes)..."
$ingressIp = ""
for ($i = 0; $i -lt 60; $i++) {
    $ingressIp = kubectl get ingress grafana -n $Namespace -o jsonpath="{.status.loadBalancer.ingress[0].ip}" 2>$null
    if ($ingressIp) { break }
    Start-Sleep -Seconds 10
}

Write-Host ""
Write-Host "Deployed. Resources in namespace $Namespace :"
kubectl get pods,svc,ingress,daemonset -n $Namespace

$b64 = kubectl get secret grafana-admin -n $Namespace -o jsonpath="{.data.admin-password}"
$plain = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($b64))
Write-Host ""
Write-Host "Grafana user: admin"
Write-Host "Grafana password: $plain"
if ($ingressIp) {
    Write-Host ""
    Write-Host "Public Grafana URL: http://$ingressIp"
} else {
    Write-Host ""
    Write-Host "Ingress IP is still provisioning. Check with:"
    Write-Host "  kubectl get ingress grafana -n $Namespace"
    Write-Host "Then open http://<ADDRESS>"
}
Write-Host ""
Write-Host "Prometheus stays cluster-internal:"
Write-Host "  kubectl -n $Namespace port-forward svc/prometheus 9090:9090"
