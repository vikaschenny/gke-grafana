# Deploy the observability stack with Helm on the current kubectl context.
param(
    [string]$ReleaseName = "observability",
    [string]$Namespace = "observability",
    [string]$ValuesFile = "",
    [switch]$Internal,
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $RepoRoot
$Chart = Join-Path $RepoRoot "helm\observability-stack"
if (-not $ValuesFile) {
    $ValuesFile = Join-Path $RepoRoot "helm\observability-stack\values-gke.yaml"
}

if (-not (Get-Command helm -ErrorAction SilentlyContinue)) {
    Write-Host "Helm is not installed. Use the no-edit path instead:"
    Write-Host "  .\scripts\deploy-gke.ps1"
    throw "helm not found on PATH"
}

if (-not (Get-Command kubectl -ErrorAction SilentlyContinue)) {
    throw "kubectl is not installed or not on PATH."
}

Write-Host "Using kube context: $(kubectl config current-context)"

$extra = @()
if ($Internal) {
    $extra += @("-f", (Join-Path $RepoRoot "helm\observability-stack\values-internal.yaml"))
}

$helmArgs = @(
    "upgrade", "--install", $ReleaseName, $Chart,
    "-n", $Namespace,
    "--create-namespace",
    "-f", $ValuesFile
) + $extra

if ($DryRun) {
    $helmArgs += "--dry-run"
    $helmArgs += "--debug"
}

helm @helmArgs

if (-not $DryRun) {
    kubectl rollout status deployment -n $Namespace -l app.kubernetes.io/component=grafana --timeout=300s
    kubectl rollout status statefulset -n $Namespace -l app.kubernetes.io/component=prometheus --timeout=300s
    kubectl rollout status daemonset -n $Namespace -l app.kubernetes.io/component=node-exporter --timeout=300s
    helm test $ReleaseName -n $Namespace
    Write-Host ""
    Write-Host "Access: kubectl -n $Namespace port-forward svc/$ReleaseName-observability-stack-grafana 3000:80"
}
