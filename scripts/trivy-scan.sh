#!/usr/bin/env bash
# Scan Docker image with Trivy — mirrors Jenkins 'Trivy Scan' stage
# Usage: ./trivy-scan.sh <image:tag>
set -euo pipefail

FULL_IMAGE="${1:?Usage: $0 <image:tag>}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
mkdir -p "${REPO_ROOT}/reports"

echo "==> Trivy: scanning ${FULL_IMAGE}..."

trivy image \
    --format json \
    --output "${REPO_ROOT}/reports/trivy-results.json" \
    --exit-code 0 \
    "${FULL_IMAGE}"

trivy image \
    --format table \
    --exit-code 0 \
    "${FULL_IMAGE}"

echo ""
echo "==> Checking for CRITICAL vulnerabilities (exit 1 if found)..."
trivy image \
    --severity CRITICAL \
    --ignore-unfixed \
    --exit-code 1 \
    "${FULL_IMAGE}"

echo "✓ Trivy scan passed"
echo "Full report: ${REPO_ROOT}/reports/trivy-results.json"
