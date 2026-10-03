#!/usr/bin/env bash
# Build Docker image locally — mirrors Jenkins 'Docker Build' stage
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

APP_NAME="${APP_NAME:-jenkinsforge}"
IMAGE_TAG="${IMAGE_TAG:-$(git -C "${REPO_ROOT}" rev-parse --short HEAD 2>/dev/null || echo "local")}"
REGISTRY="${REGISTRY:-${APP_NAME}}"
FULL_IMAGE="${REGISTRY}:${IMAGE_TAG}"

echo "==> Building: ${FULL_IMAGE}"
docker build \
    --build-arg APP_VERSION="${IMAGE_TAG}" \
    --label "org.opencontainers.image.revision=$(git -C "${REPO_ROOT}" rev-parse HEAD 2>/dev/null || echo unknown)" \
    -t "${FULL_IMAGE}" \
    "${REPO_ROOT}/app/"

echo "✓ Image built: $(docker image inspect "${FULL_IMAGE}" --format '{{.Id}}')"
echo "FULL_IMAGE=${FULL_IMAGE}"
