# Deployment Guide

## Deployment Architecture

```
ECR (image registry)
        │
        │  docker pull
        ▼
EC2 Docker Host (deployment target)
        │
        │  docker run
        ▼
  Container: jenkinsforge
  Port: 8000
  User: app (UID 1001, non-root)
```

The deployment is intentionally simple: one container, one host, one port.
The focus is on **pipeline gates**, not infrastructure complexity.

---

## Deployment Flow (Jenkins)

1. All CI and security stages pass (Test → Lint → SAST → Dep Scan → Build → Trivy → SBOM)
2. Image is pushed to ECR with two tags:
   - `:a1b2c3d4` — Git commit SHA (primary tag)
   - `:build-42` — Jenkins build number (secondary reference)
3. The digest ECR reports is recorded; from here on only that digest is used
4. Cosign signs the digest (the signature is stored in ECR) and verifies it
5. Jenkins SSHes to the deployment host
6. An ECR auth token is piped over SSH stdin to the remote `docker login`
7. `docker pull <digest>`, replace the previous container, `docker run`
8. Verify polls `/health` for up to 60 s and asserts `status=healthy` and `version=<git sha>`

The `Deploy` and `Verify` stages **only execute on the `main` branch** (or when
`FORCE_DEPLOY=true` is set as a pipeline parameter).

### Local deploy target (no EC2 needed)

[`local-deploy-target/`](../local-deploy-target/) builds a stand-in deployment host:
its own Docker engine (Docker-in-Docker) reachable only over SSH as user `deploy`
with key auth. Run it on the Jenkins Docker host (commands are in its Dockerfile
header), then set the `deploy-host` credential to `jf-deploy-target` and
`deploy-ssh-key` to the matching private key. The deployed service is published on
the host at `http://localhost:8001/health`.

---

## Manual Deployment

```bash
export ECR_REGISTRY="123456789012.dkr.ecr.us-east-1.amazonaws.com"
export IMAGE_TAG="a1b2c3d4"  # git commit SHA
export FULL_IMAGE="${ECR_REGISTRY}/jenkinsforge:${IMAGE_TAG}"

# Authenticate with ECR
aws ecr get-login-password --region us-east-1 | \
    docker login --username AWS --password-stdin "${ECR_REGISTRY}"

# Pull and run
docker pull "${FULL_IMAGE}"
docker stop jenkinsforge 2>/dev/null || true
docker rm   jenkinsforge 2>/dev/null || true
docker run -d \
    --name jenkinsforge \
    --restart unless-stopped \
    -p 8000:8000 \
    -e APP_VERSION="${IMAGE_TAG}" \
    "${FULL_IMAGE}"

# Verify
curl http://localhost:8000/health
```

---

## Deployment Verification

The Verify stage checks:

1. HTTP `GET /health` returns **200 OK**
2. Response body contains `"status": "healthy"`
3. Response body contains `"service": "jenkinsforge"`

```bash
# Manual verification
curl -s http://<deploy-host>:8000/health | python3 -m json.tool
```

Expected response:
```json
{
    "service": "jenkinsforge",
    "version": "a1b2c3d4",
    "status": "healthy"
}
```

If verification fails, the Verify stage fails and the Jenkins build is marked FAILED.

---

## Rollback

### Quick rollback to previous image

```bash
# List recent ECR images
aws ecr describe-images \
    --repository-name jenkinsforge \
    --region us-east-1 \
    --query 'reverse(sort_by(imageDetails, &imagePushedAt))[*].{Tag:imageTags[0],Pushed:imagePushedAt}' \
    --output table

# Roll back to a specific tag
export PREVIOUS_TAG="<previous-commit-sha>"
export ECR_REGISTRY="123456789012.dkr.ecr.us-east-1.amazonaws.com"

aws ecr get-login-password --region us-east-1 | \
    docker login --username AWS --password-stdin "${ECR_REGISTRY}"

docker pull "${ECR_REGISTRY}/jenkinsforge:${PREVIOUS_TAG}"
docker stop jenkinsforge
docker rm   jenkinsforge
docker run -d \
    --name jenkinsforge \
    --restart unless-stopped \
    -p 8000:8000 \
    "${ECR_REGISTRY}/jenkinsforge:${PREVIOUS_TAG}"

curl http://localhost:8000/health
```

### Why rollback works

Because every deployed image uses an immutable Git-SHA tag (not `latest`), previous
versions remain accessible in ECR for the lifecycle policy retention period.

---

## ECR Image Lifecycle

See `iam/ecr-lifecycle-policy.json`.

Default policy retains:
- Last **10 tagged images** (untagged images expire after 1 day)
- This prevents ECR storage from growing unbounded

---

## Environment Variables

| Variable      | Default   | Description                           |
|---------------|-----------|---------------------------------------|
| `APP_VERSION` | `1.0.0`   | Set to the image tag at deploy time   |
| `LOG_LEVEL`   | `INFO`    | Application log level                 |
| `PORT`        | `8000`    | Application port (container internal) |

---

## Ports

| Port | Protocol | Description        |
|------|----------|--------------------|
| 8000 | TCP/HTTP | Application HTTP   |

Only port 8000 is exposed. TLS termination should be handled by a load balancer
or reverse proxy in front of the container.

---

## Failure Demonstration: Deployment Verification Failure

See `docs/failure-demos.md#deployment-verification-failure`.
