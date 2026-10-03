#!/usr/bin/env bash
# Run linter locally — mirrors Jenkins 'Lint' stage
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

cd "${REPO_ROOT}/app"

echo "==> Installing ruff..."
pip install ruff -q

echo "==> ruff check (style + imports)..."
ruff check src/ tests/

echo "==> ruff format check..."
ruff format --check src/ tests/

echo "✓ Lint passed"
