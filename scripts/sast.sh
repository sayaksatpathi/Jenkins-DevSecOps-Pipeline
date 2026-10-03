#!/usr/bin/env bash
# Run SAST locally — mirrors Jenkins 'SAST' stage
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

mkdir -p "${REPO_ROOT}/reports"

echo "==> Installing Semgrep..."
pip install semgrep -q

echo "==> Running Semgrep on app/src/..."
semgrep scan \
    --config p/python \
    --config p/owasp-top-ten \
    --config p/secrets \
    --sarif \
    --output "${REPO_ROOT}/reports/semgrep-results.sarif" \
    --error \
    "${REPO_ROOT}/app/src/"

echo "✓ SAST passed"
echo "Report: ${REPO_ROOT}/reports/semgrep-results.sarif"
