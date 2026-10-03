#!/usr/bin/env bash
# Run unit tests locally — mirrors Jenkins 'Unit Test' stage
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

cd "${REPO_ROOT}/app"

echo "==> Installing dev dependencies..."
pip install -r requirements-dev.txt -q

echo "==> Running tests..."
mkdir -p ../reports
pytest tests/ \
    --junitxml=../reports/test-results.xml \
    -v --tb=short --color=yes

echo "Test results: ${REPO_ROOT}/reports/test-results.xml"
