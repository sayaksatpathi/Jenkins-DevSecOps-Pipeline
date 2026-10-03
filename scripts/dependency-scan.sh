#!/usr/bin/env bash
# Scan Python dependencies for CVEs — mirrors Jenkins 'Dependency Scan' stage
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

mkdir -p "${REPO_ROOT}/reports"

echo "==> Installing pip-audit..."
pip install pip-audit -q

echo "==> Scanning app/requirements.txt for known vulnerabilities..."
pip-audit \
    -r "${REPO_ROOT}/app/requirements.txt" \
    --format json \
    --output "${REPO_ROOT}/reports/pip-audit-results.json" \
    --progress-spinner off

echo "✓ Dependency scan passed"
echo "Report: ${REPO_ROOT}/reports/pip-audit-results.json"
