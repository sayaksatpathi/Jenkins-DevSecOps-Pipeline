# Build #13 — first fully green run (2026-10-05)

Jenkins 2.580.1 · commit `7e9e0a7` · total runtime 8 min 25 s · result **SUCCESS**

These files are the archived artifacts and console log of the run, downloaded
unchanged from Jenkins except that the AWS account ID is replaced with
`<aws-account-id>`. Secrets were masked by Jenkins (`****`) at run time.

## Stages

| # | Stage | Status | Duration |
|---|-------|--------|----------|
| 1 | Checkout | SUCCESS | 1s |
| 2 | Unit Test | SUCCESS | 50s |
| 3 | Lint | SUCCESS | 16s |
| 4 | SAST | SUCCESS | 115s |
| 5 | Dependency Scan | SUCCESS | 46s |
| 6 | Docker Build | SUCCESS | 24s |
| 7 | Trivy Scan | SUCCESS | 3s |
| 8 | SBOM | SUCCESS | 6s |
| 9 | Push to ECR | SUCCESS | 117s |
| 10 | Sign Image | SUCCESS | 15s |
| 11 | Deploy | SUCCESS | 94s |
| 12 | Verify | SUCCESS | 5s |

## Key results

| Check | Result | File |
|-------|--------|------|
| Unit tests | 14 passed | `test-results.xml` |
| SAST (Semgrep) | no blocking findings | `semgrep-results.sarif` |
| Dependency scan (pip-audit, report-only) | 14 known vulns reported | `pip-audit-results.json` |
| Image scan (Trivy) | **0 CRITICAL** (gate passed); 48 HIGH remain in base-image packages | `trivy-table.txt`, `trivy-results.json` |
| SBOM | CycloneDX + SPDX | `sbom-cyclonedx.json`, `sbom-spdx.json` |
| ECR digest | `sha256:68f32fde063236b12df13197ba7fda6aa515efcf60ca3aa59a1dc092d1eaac45` | `image-digest.txt` |
| Signature | verified against the public key, by digest | `cosign-verify.json`, `cosign.pub` |
| Deployed health | `{"service":"jenkinsforge","version":"7e9e0a7","status":"healthy"}` | `console.log` |

Verify the signature yourself (with registry access):

```bash
cosign verify --key cosign.pub <aws-account-id>.dkr.ecr.us-east-1.amazonaws.com/jenkinsforge@sha256:68f32fde063236b12df13197ba7fda6aa515efcf60ca3aa59a1dc092d1eaac45
```

The deploy target for this run was the [local SSH deploy host](../../local-deploy-target/).
