#!/usr/bin/env bash
# Deploy a container image to the EC2 Docker host via SSH
# Usage: ./deploy.sh <image:tag>
# Env:   SSH_KEY, SSH_USER, DEPLOY_HOST, ECR_REGISTRY, AWS_REGION
#        AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY
set -euo pipefail

FULL_IMAGE="${1:?Usage: $0 <image:tag>}"
APP_NAME="${APP_NAME:-jenkinsforge}"

: "${SSH_KEY:?SSH_KEY must be set}"
: "${SSH_USER:?SSH_USER must be set}"
: "${DEPLOY_HOST:?DEPLOY_HOST must be set}"
: "${ECR_REGISTRY:?ECR_REGISTRY must be set}"
: "${AWS_REGION:?AWS_REGION must be set}"

echo "==> Authenticating with ECR..."
ECR_PASSWORD=$(aws ecr get-login-password --region "${AWS_REGION}")

echo "==> Deploying ${FULL_IMAGE} to ${DEPLOY_HOST}..."
ssh -i "${SSH_KEY}" \
    -o StrictHostKeyChecking=no \
    -o ConnectTimeout=30 \
    "${SSH_USER}@${DEPLOY_HOST}" bash -s << REMOTE
set -e
echo '${ECR_PASSWORD}' | docker login \
    --username AWS \
    --password-stdin '${ECR_REGISTRY}'

docker pull '${FULL_IMAGE}'
docker stop '${APP_NAME}' 2>/dev/null || true
docker rm   '${APP_NAME}' 2>/dev/null || true
docker run -d \
    --name '${APP_NAME}' \
    --restart unless-stopped \
    -p 8000:8000 \
    '${FULL_IMAGE}'
docker ps --filter "name=${APP_NAME}"
echo "Deployment complete on \$(hostname)"
REMOTE

echo "✓ Deployment complete"
