#!/usr/bin/env bash
# Generate SBOM for a Docker image — mirrors Jenkins 'SBOM' stage
# Usage: ./sbom.sh <image:tag>
set -euo pipefail

FULL_IMAGE="${1:?Usage: $0 <image:tag>}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
mkdir -p "${REPO_ROOT}/reports"

echo "==> Syft: generating SBOM for ${FULL_IMAGE}..."
syft "${FULL_IMAGE}" \
    -o cyclonedx-json="${REPO_ROOT}/reports/sbom-cyclonedx.json" \
    -o spdx-json="${REPO_ROOT}/reports/sbom-spdx.json"

COMPONENTS=$(python3 -c "
import json
with open('${REPO_ROOT}/reports/sbom-cyclonedx.json') as f:
    d = json.load(f)
print(len(d.get('components', [])))
")

echo "✓ SBOM generated: ${COMPONENTS} components"
echo "  CycloneDX: ${REPO_ROOT}/reports/sbom-cyclonedx.json"
echo "  SPDX:      ${REPO_ROOT}/reports/sbom-spdx.json"
