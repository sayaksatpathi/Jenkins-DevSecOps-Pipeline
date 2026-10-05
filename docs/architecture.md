# Architecture

## Overview

JenkinsForge is a **Jenkins-based DevSecOps pipeline** that demonstrates continuous integration,
security scanning, container image management, and verified deployment — all driven by
Pipeline-as-Code stored in Git.

The application deliberately remains small (two HTTP endpoints) so the **pipeline is the project**.

---

## System Architecture

```
Developer
    │
    │ git push / PR
    ▼
GitHub
    │
    │ webhook (HMAC-SHA256 signed)
    ▼
Jenkins Controller
    │
    ▼
Jenkins Pipeline (Jenkinsfile)
    │
    ├─ Stage 1:  Checkout
    │               └── git rev for immutable tag
    │
    ├─ Stage 2:  Unit Test ─────────────── (Docker: python:3.12-slim)
    │               └── pytest → JUnit XML
    │
    ├─ Stage 3:  Lint ──────────────────── (Docker: python:3.12-slim)
    │               └── ruff check + format
    │
    ├─ Stage 4:  SAST ──────────────────── (Docker: python:3.12-slim)
    │               └── semgrep p/python + p/owasp-top-ten + p/secrets
    │                         → SARIF report
    │
    ├─ Stage 5:  Dependency Scan ───────── (Docker: python:3.12-slim)
    │               └── pip-audit → JSON report
    │
    ├─ Stage 6:  Docker Build ──────────── (Jenkins agent: docker daemon)
    │               └── multi-stage Dockerfile → tagged image
    │
    ├─ Stage 7:  Trivy Scan ────────────── (Jenkins agent: trivy installed)
    │               └── OS + app CVE scan → JSON + table report
    │                   CRITICAL vulns → pipeline blocked
    │
    ├─ Stage 8:  SBOM ──────────────────── (Jenkins agent: syft installed)
    │               └── syft → CycloneDX + SPDX JSON (archived)
    │
    ├─ Stage 9:  Push to ECR ───────────── (Jenkins agent: aws cli + docker)
    │               └── ecr get-login-password → docker push
    │                   → record immutable digest (reports/image-digest.txt)
    │
    ├─ Stage 10: Sign Image ────────────── (Jenkins agent: cosign installed)
    │               └── cosign sign + verify, by digest
    │                   (signature is stored in ECR beside the image)
    │
    ├─ Stage 11: Deploy ────────────────── (Jenkins agent: ssh + aws cli)
    │               └── SSH → Docker host → docker run <signed digest>
    │               [only on: main branch OR FORCE_DEPLOY=true]
    │
    └─ Stage 12: Verify
                    └── curl /health → assert status=healthy + version=<git sha>
                    [only on: main branch OR FORCE_DEPLOY=true]
                              │
                 ┌────────────┴────────────┐
                 │                         │
             Healthy                  Failed
                 │                         │
                 ▼                         ▼
           Pipeline SUCCESS         Verify stage fails
                                    (rollback required)
```

---

## Security Gate Map

| Gate             | Tool        | Blocking?              | Artifact                      |
|------------------|-------------|------------------------|-------------------------------|
| Unit Tests       | pytest      | Yes — stops pipeline   | reports/test-results.xml      |
| Lint             | ruff        | Yes — stops pipeline   | console output                |
| SAST             | semgrep     | Yes — stops pipeline   | reports/semgrep-results.sarif |
| Dependency CVEs  | pip-audit   | Yes — stops pipeline   | reports/pip-audit-results.json |
| Image CVEs       | trivy       | Yes (CRITICAL unfixed) | reports/trivy-results.json    |
| SBOM             | syft        | Yes — stops pipeline   | reports/sbom-cyclonedx.json   |
| Image Signature  | cosign      | Yes — stops pipeline   | OCI registry annotation       |
| Health Check     | curl        | Yes — rejects deploy   | console output                |

---

## Component Roles

| Component         | Role                                                        |
|-------------------|-------------------------------------------------------------|
| GitHub            | Source of truth; webhook trigger; PR quality gate surface   |
| Jenkins           | CI/CD orchestrator; credential store; artifact archive      |
| Python/FastAPI    | Application under test; intentionally minimal               |
| pytest            | Unit tests; failure blocks deployment                       |
| ruff              | Python linter and formatter                                 |
| Semgrep           | SAST; OWASP Top 10 + secrets rules                         |
| pip-audit         | Python dependency CVE scanner                               |
| Docker            | Image build and runtime                                     |
| Trivy             | Container image vulnerability scanner                       |
| Syft              | SBOM generator (CycloneDX + SPDX)                          |
| Cosign            | Container image signing and verification                    |
| Amazon ECR        | Immutable container image registry                          |
| EC2 Docker host   | Deployment target                                           |
| AWS CLI           | ECR authentication and image metadata queries               |

---

## Traceability

Every deployed container is traceable end-to-end:

```
Git commit SHA
    │
    ├─ → Docker image tag (e.g. :a1b2c3d4)
    ├─ → Jenkins build number label
    ├─ → ECR image metadata (imageDigest)
    ├─ → Cosign signature annotation
    └─ → Running container labels
```

`latest` is never the only reference to a deployed artifact.
