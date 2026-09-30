# Deploy raw Kubernetes manifests (Kustomize) on the current kubectl context.
# No file edits required. Run from anywhere.
param(
    [string]$Namespace = "observability",
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Parent $PSScriptRoot
& (Join-Path $PSScriptRoot "deploy-gke.ps1") -Namespace $Namespace -DryRun:$DryRun
