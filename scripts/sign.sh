#!/usr/bin/env bash
# Sign and verify a container image with Cosign
# Usage: ./sign.sh <image:tag> <cosign-key-path>
# Env:   COSIGN_PASSWORD — key passphrase
set -euo pipefail

FULL_IMAGE="${1:?Usage: $0 <image:tag> [key-path]}"
COSIGN_KEY="${2:-cosign.key}"

echo "==> Cosign: signing ${FULL_IMAGE} with key ${COSIGN_KEY}..."
cosign sign --yes \
    --key "${COSIGN_KEY}" \
    "${FULL_IMAGE}"

echo "==> Cosign: verifying signature..."
cosign verify \
    --key "${COSIGN_KEY}" \
    "${FULL_IMAGE}"

echo "✓ Image signed and signature verified: ${FULL_IMAGE}"
echo ""
echo "Public key for verification: ${COSIGN_KEY%.key}.pub"
echo "Distribute cosign.pub to consumers for offline verification."
