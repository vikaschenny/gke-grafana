#!/usr/bin/env bash
# Wrapper for the no-edit GKE deploy.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "${SCRIPT_DIR}/deploy-gke.sh" "$@"
