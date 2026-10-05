# Failure Demonstrations

This document describes how each security/quality gate blocks deployment.
All demonstrations are reversible.

---

## 1. Unit Test Failure

### Setup

Introduce a deliberate test failure by editing `app/tests/test_main.py`:

```python
def test_root_status_value():
    # Changed from "ok" to "ready" — will fail
    assert client.get("/").json()["status"] == "ready"
```

### Expected Pipeline Behavior

```
Stage 1:  Checkout       ✓ PASS
Stage 2:  Unit Test      ✗ FAIL  ← pytest AssertionError
Stage 3:  Lint           SKIPPED
Stage 4:  SAST           SKIPPED
Stage 5:  Dependency Scan SKIPPED
Stage 6:  Docker Build   SKIPPED
Stage 7:  Trivy Scan     SKIPPED
Stage 8:  SBOM           SKIPPED
Stage 9:  Push to ECR    SKIPPED ← no image pushed
Stage 10: Sign Image     SKIPPED
Stage 11: Deploy         SKIPPED ← no deployment
Stage 12: Verify         SKIPPED

BUILD RESULT: FAILURE
```

Jenkins publishes the JUnit test report showing the specific failing test.

### Restore

```bash
# Revert the change
git checkout app/tests/test_main.py
git push origin main
```

---

## 2. SAST Failure (Hardcoded Secret)

### Setup

Introduce a hardcoded secret that Semgrep's `p/secrets` rule will flag.
Edit `app/src/main.py` and add:

```python
# deliberate-sast-fail: hardcoded credential for testing
INTERNAL_API_KEY = "sk-hardcoded-secret-key-for-demo-only"
```

### Expected Pipeline Behavior

```
Stage 1:  Checkout        ✓ PASS
Stage 2:  Unit Test       ✓ PASS
Stage 3:  Lint            ✓ PASS
Stage 4:  SAST            ✗ FAIL  ← semgrep: hardcoded secret
Stage 5:  Dependency Scan SKIPPED
Stage 6:  Docker Build    SKIPPED ← no image built
Stage 9:  Push to ECR     SKIPPED ← no image pushed
Stage 11: Deploy          SKIPPED ← no deployment

BUILD RESULT: FAILURE
```

SARIF report archived — finding visible in Jenkins artifacts.

### Restore

```bash
git checkout app/src/main.py
git push origin main
```

---

## 3. Dependency Scan Failure (Vulnerable Package)

### Setup

Pin a known-vulnerable version of a dependency:

```
# app/requirements.txt
fastapi==0.100.0   # older version, check pip-audit database
uvicorn[standard]==0.23.0
```

> Note: The specific versions with known CVEs change over time. Check the
> [pip-audit advisory database](https://osv.dev) for currently vulnerable versions.

### Expected Pipeline Behavior

```
Stage 5: Dependency Scan  ✗ FAIL  ← pip-audit: CVE-XXXX found in <package>
Stage 6: Docker Build      SKIPPED
...
Stage 11: Deploy           SKIPPED

BUILD RESULT: FAILURE
```

### Restore

```bash
git checkout app/requirements.txt
git push origin main
```

---

## 4. Trivy Scan Failure (Vulnerable Base Image)

### Setup

Change the Dockerfile to use a known-vulnerable base image:

```dockerfile
# Deliberately old image with known CVEs
FROM python:3.9-slim AS builder
FROM python:3.9-slim AS runtime
```

Then rebuild. The old Python 3.9-slim image contains OS packages with CRITICAL CVEs.

### Expected Pipeline Behavior

```
Stage 6:  Docker Build   ✓ PASS
Stage 7:  Trivy Scan     ✗ FAIL  ← CRITICAL vulns found, exit-code 1
Stage 8:  SBOM           SKIPPED
Stage 9:  Push to ECR    SKIPPED ← vulnerable image never pushed
Stage 10: Sign Image     SKIPPED
Stage 11: Deploy         SKIPPED ← vulnerable image never deployed

BUILD RESULT: FAILURE
```

### Restore

```bash
git checkout app/Dockerfile
git push origin main
```

---

## 5. Deployment Verification Failure

### Setup

Modify the health endpoint to return a non-healthy status temporarily.
Edit `app/src/main.py`:

```python
@app.get("/health")
async def health() -> dict:
    return {
        "service": settings.APP_NAME,
        "version": settings.VERSION,
        "status": "degraded",   # changed from "healthy"
    }
```

### Expected Pipeline Behavior

```
Stage 1–10: All pass (tests are updated to accept "degraded" — or not, in which case
            this fails at Unit Test)
Stage 11: Deploy     ✓ PASS  ← container starts
Stage 12: Verify     ✗ FAIL  ← status != "healthy"

BUILD RESULT: FAILURE
```

The Verify stage logs the assertion failure and prints rollback instructions.

The previous container version (which did pass verification) remains available
in ECR for rollback using the procedure in `docs/deployment.md#rollback`.

### Restore

```bash
git checkout app/src/main.py
git push origin main
```

---

## 6. Lint Failure

### Setup

Introduce a style violation:

```python
# app/src/main.py — add an unused import
import os
import this  # unused import flagged by ruff
```

### Expected Pipeline Behavior

```
Stage 3: Lint  ✗ FAIL  ← ruff: F401 unused import
```

### Restore

```bash
git checkout app/src/main.py
git push origin main
```

---

## Failure/Success Matrix

| Stage            | Failure Result             | Deployment Allowed? |
|------------------|----------------------------|---------------------|
| Checkout         | Build fails                | No                  |
| Unit Test        | Build fails                | No                  |
| Lint             | Build fails                | No                  |
| SAST             | Security gate fails        | No                  |
| Dependency Scan  | Security gate fails        | No                  |
| Docker Build     | Build fails                | No                  |
| Trivy            | Security gate fails        | No                  |
| SBOM             | Build fails                | No                  |
| Push to ECR      | Delivery fails             | No                  |
| Sign Image       | Build fails                | No                  |
| Deploy           | Deployment fails           | No                  |
| Verify           | Deployment rejected        | No (rollback)       |
