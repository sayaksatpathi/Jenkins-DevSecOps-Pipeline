#!/usr/bin/env bash
# Verify deployment health — mirrors Jenkins 'Verify' stage
# Usage: ./verify.sh <host> [port]
set -euo pipefail

HOST="${1:?Usage: $0 <host> [port]}"
PORT="${2:-8000}"
URL="http://${HOST}:${PORT}/health"

echo "==> Health check: ${URL}"

HTTP_STATUS=$(curl -sf -o /dev/null -w '%{http_code}' \
    --connect-timeout 10 --max-time 20 \
    "${URL}" || echo "000")

if [ "${HTTP_STATUS}" != "200" ]; then
    echo "✗ Health check failed: HTTP ${HTTP_STATUS}"
    exit 1
fi

RESPONSE=$(curl -sf --connect-timeout 10 "${URL}")
echo "Response: ${RESPONSE}"

python3 - << PY
import json, sys
d = json.loads('${RESPONSE}')
assert d.get('status') == 'healthy', f"Expected 'healthy', got: {d.get('status')}"
print(f"  service: {d['service']}")
print(f"  version: {d['version']}")
print(f"  status:  {d['status']}")
PY

echo "✓ Deployment verified: ${URL}"
