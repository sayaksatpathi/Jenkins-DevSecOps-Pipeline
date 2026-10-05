# JenkinsForge — Container DevSecOps Pipeline

A focused Jenkins-based DevSecOps portfolio project demonstrating a **complete
Pipeline-as-Code workflow** from code commit to verified deployment, with real security
gates at every step.

> The application is intentionally small.  
> **The pipeline is the project.**

---

## Pipeline Overview

```
Developer
    │
    │  git push / Pull Request
    ▼
GitHub ──── webhook (HMAC-SHA256) ────► Jenkins
                                            │
                    ┌───────────────────────┼──────────────────────┐
                    │                       │                      │
                    ▼                       ▼                      ▼
              Unit Test               SAST                  Dependency
              (pytest)           (semgrep)                 Scan (pip-audit)
                    │                       │                      │
                    └───────────────────────┼──────────────────────┘
                                            │
                                            ▼
                                      Docker Build
                                            │
                                            ▼
                                       Trivy Scan ──── CRITICAL? ──► BLOCK
                                            │
                                            ▼
                                          SBOM
                                       (syft → CycloneDX + SPDX)
                                            │
                                            ▼
                                        Push ECR
                                    (:sha + :build-N)
                                            │
                                            ▼
                                       Sign Image
                                   (cosign, by digest)
                                            │
                                            ▼
                                         Deploy
                                    (SSH → docker run)
                                            │
                                            ▼
                                         Verify
                                      (curl /health)
                                            │
                             ┌──────────────┴──────────────┐
                             │                             │
                          HEALTHY                       FAILED
                             │                             │
                        Pipeline ✓               Rejected + Rollback
```

---

## Tech Stack

| Layer            | Tool                    | Purpose                                      |
|------------------|-------------------------|----------------------------------------------|
| CI/CD            | Jenkins                 | Pipeline orchestration                       |
| VCS              | GitHub                  | Source of truth; webhook trigger             |
| Application      | Python / FastAPI        | Service under test                           |
| Unit Tests       | pytest                  | Test gate — failures block deployment        |
| Lint             | ruff                    | Style + import checks                        |
| SAST             | Semgrep                 | Static security analysis (OWASP Top 10)      |
| Dep Scanning     | pip-audit               | Python dependency CVE scanning               |
| Container Build  | Docker (multi-stage)    | Minimal, non-root, production image          |
| Image Scanning   | Trivy                   | OS + app vulnerability scanning              |
| SBOM             | Syft                    | CycloneDX + SPDX software bill of materials  |
| Image Signing    | Cosign                  | Cryptographic container image signing        |
| Registry         | Amazon ECR              | Immutable tagged image storage               |
| Deployment       | SSH + Docker            | Any Docker host over SSH (EC2 or [local target](local-deploy-target/)) |
| Verification     | curl + Python           | Post-deploy health check gate                |

---

## Pipeline Stages

| # | Stage            | Tool       | Gate?                    | Artifact                          |
|---|------------------|------------|--------------------------|-----------------------------------|
| 1 | Checkout         | git        | —                        | `GIT_SHORT_SHA` → image tag       |
| 2 | Unit Test        | pytest     | ✓ Fail = stop            | `reports/test-results.xml`        |
| 3 | Lint             | ruff       | ✓ Fail = stop            | Console output                    |
| 4 | SAST             | semgrep    | ✓ Fail = stop            | `reports/semgrep-results.sarif`   |
| 5 | Dependency Scan  | pip-audit  | ✓ Fail = stop            | `reports/pip-audit-results.json`  |
| 6 | Docker Build     | docker     | ✓ Fail = stop            | Tagged OCI image                  |
| 7 | Trivy Scan       | trivy      | ✓ CRITICAL = stop        | `reports/trivy-results.json`      |
| 8 | SBOM             | syft       | ✓ Fail = stop            | `reports/sbom-cyclonedx.json`     |
| 9 | Push to ECR      | aws cli    | ✓ Fail = stop            | ECR image + `reports/image-digest.txt` |
|10 | Sign Image       | cosign     | ✓ Fail = stop            | Signature in ECR, verified by digest |
|11 | Deploy           | ssh+docker | ✓ Fail = stop            | Signed digest running on deploy host |
|12 | Verify           | curl       | ✓ Fail = rollback needed | Health response                   |

---

## Security Gates

Any gate failure **stops the pipeline immediately** — no code reaches deployment
unless every gate passes.

```
Test failure       → Unit Test stage fails    → no Docker build
SAST finding       → SAST stage fails         → no Docker build
Vulnerable dep     → Dep Scan fails           → no Docker build
Critical CVE       → Trivy stage fails        → no ECR push
Signing failure    → Sign stage fails         → no deployment
Health check fail  → Verify stage fails       → deployment rejected
```

---

## Quick Start (Local)

```bash
# Clone
git clone https://github.com/sayaksatpathi/Jenkins-DevSecOps-Pipeline.git
cd Jenkins-DevSecOps-Pipeline

# Install Python dependencies
make install

# Run all CI stages locally
make ci

# Build and scan the Docker image
make docker-build trivy sbom

# Run the application
make run
# → http://localhost:8000/health
```

---

## Credentials Setup

Before running the pipeline, configure these Jenkins credentials.  
See [docs/jenkins-setup.md](docs/jenkins-setup.md) for detailed instructions.

| Credential ID          | Type                       | Description                           |
|------------------------|----------------------------|---------------------------------------|
| `ecr-registry`         | Secret text                | ECR registry URL                      |
| `aws-access-key-id`    | Secret text                | AWS IAM access key                    |
| `aws-secret-access-key`| Secret text                | AWS IAM secret key                    |
| `deploy-host`          | Secret text                | Deployment host IP or hostname        |
| `deploy-ssh-key`       | SSH Username with key      | SSH key for deployment host           |
| `cosign-private-key`   | Secret file                | cosign.key (generated locally)        |
| `cosign-password`      | Secret text                | cosign key passphrase                 |

The two AWS credentials can be issued and stored in one step, without the secret
ever being displayed, by [`scripts/setup-jenkins-aws-credentials.sh`](scripts/setup-jenkins-aws-credentials.sh).

**No credentials appear in source code or documentation.**

---

## Application Endpoints

| Endpoint  | Method | Response                                                       |
|-----------|--------|----------------------------------------------------------------|
| `/`       | GET    | `{"service":"jenkinsforge","version":"<tag>","status":"ok"}`  |
| `/health` | GET    | `{"service":"jenkinsforge","version":"<tag>","status":"healthy"}` |

---

## Repository Structure

```
Jenkins-DevSecOps-Pipeline/
│
├── app/                        Application
│   ├── src/
│   │   ├── __init__.py
│   │   ├── main.py             FastAPI routes (/ and /health)
│   │   └── config.py           Settings (version, log level)
│   ├── tests/
│   │   └── test_main.py        14 pytest test cases
│   ├── Dockerfile              Multi-stage, non-root
│   ├── .dockerignore
│   ├── requirements.txt        Production dependencies
│   ├── requirements-dev.txt    Dev + test dependencies
│   └── pyproject.toml          ruff config
│
├── Jenkinsfile                 Pipeline-as-Code (12 stages)
│
├── scripts/                    Local reproduction of pipeline stages
│   ├── test.sh
│   ├── lint.sh
│   ├── sast.sh
│   ├── dependency-scan.sh
│   ├── build.sh
│   ├── trivy-scan.sh
│   ├── sbom.sh
│   ├── sign.sh
│   ├── deploy.sh
│   └── verify.sh
│
├── docs/
│   ├── architecture.md         System design and stage map
│   ├── jenkins-setup.md        Setup from scratch
│   ├── security.md             Security policy and credential management
│   ├── deployment.md           Deployment and rollback procedures
│   ├── troubleshooting.md      Common problems and solutions
│   └── failure-demos.md        How to reproduce each security gate failure
│
├── iam/
│   ├── jenkins-iam-policy.json Least-privilege ECR IAM policy
│   └── ecr-lifecycle-policy.json ECR image lifecycle rules
│
├── reports/                    Generated by pipeline (gitignored)
├── screenshots/                Evidence captures from Jenkins runs
│
├── Makefile                    Local development commands
└── README.md
```

---

## CI/CD Boundary

| Phase | Stages                                  | What it proves          |
|-------|-----------------------------------------|-------------------------|
| CI    | Checkout → Test → Lint → SAST → Dep Scan → Build → Trivy → SBOM → Sign | Code quality and security are verified |
| CD    | Push to ECR → Deploy → Verify           | Delivery and correctness of deployment |

---

## Failure Demonstrations

See [docs/failure-demos.md](docs/failure-demos.md) for step-by-step reproduction of:

1. **Unit test failure** — broken assertion stops pipeline at stage 2
2. **SAST failure** — hardcoded secret stops pipeline at stage 4
3. **Dependency scan failure** — known CVE stops pipeline at stage 5
4. **Trivy failure** — vulnerable base image stops pipeline at stage 7
5. **Deployment verification failure** — degraded health stops pipeline at stage 12

---

## Image Traceability

```
Git commit:  a1b2c3d4
    │
    ├─ ECR image tag:   jenkinsforge:a1b2c3d4
    ├─ ECR image tag:   jenkinsforge:build-42
    ├─ OCI label:       org.opencontainers.image.revision=a1b2c3d4
    ├─ Container label: deploy.commit=a1b2c3d4
    ├─ Container label: deploy.build=42
    └─ Cosign signature stored as OCI manifest in ECR
```

---

## Cleanup

```bash
# Remove ECR repository and all images
aws ecr delete-repository \
    --repository-name jenkinsforge \
    --region us-east-1 \
    --force

# Stop and remove the deployment container
ssh ec2-user@<deploy-host> "docker stop jenkinsforge && docker rm jenkinsforge"

# Delete the IAM user (if created)
aws iam delete-user --user-name jenkins-ecr-push
```

---

## Setup

See [docs/jenkins-setup.md](docs/jenkins-setup.md) for complete setup instructions including:
- Jenkins installation
- Required plugins
- Credentials configuration
- Cosign key generation
- GitHub webhook setup
- ECR repository creation
- Deployment host configuration

---

## Documentation

| Document                              | Contents                            |
|---------------------------------------|-------------------------------------|
| [docs/architecture.md](docs/architecture.md)       | System design, stage map, traceability |
| [docs/jenkins-setup.md](docs/jenkins-setup.md)     | Complete setup guide                |
| [docs/security.md](docs/security.md)               | Security policy, credential management |
| [docs/deployment.md](docs/deployment.md)           | Deployment and rollback procedures  |
| [docs/troubleshooting.md](docs/troubleshooting.md) | Common problems and solutions       |
| [docs/failure-demos.md](docs/failure-demos.md)     | How to reproduce each gate failure  |
