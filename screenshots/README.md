# Screenshots

This directory holds evidence captures from Jenkins pipeline runs.

The text evidence for the first fully green run (console log, test, SAST, Trivy,
SBOM and cosign reports) is already committed in [`../evidence/build-13/`](../evidence/build-13/).

## Required Screenshots

Capture these from an actual Jenkins instance after the pipeline runs:

```
screenshots/
├── successful-build/
│   ├── 01-pipeline-overview.png        Jenkins Stage View showing all 12 stages green
│   ├── 02-test-results.png             JUnit test report
│   ├── 03-sast-report.png              Semgrep SARIF archived in artifacts
│   ├── 04-trivy-results.png            Trivy scan output
│   ├── 05-sbom-artifact.png            SBOM JSON in Jenkins artifacts
│   ├── 06-ecr-image.png                ECR repository showing the pushed image
│   └── 07-health-verify.png            Verify stage console output
│
├── failed-test/
│   ├── 01-pipeline-stopped.png         Pipeline stopped at Unit Test stage
│   └── 02-junit-failure.png            JUnit report showing the failing test
│
├── security-gate/
│   ├── 01-sast-failure.png             Pipeline stopped at SAST stage
│   ├── 02-dependency-failure.png       Pipeline stopped at Dependency Scan
│   └── 03-trivy-failure.png            Pipeline stopped at Trivy scan
│
└── deployment/
    ├── 01-deploy-stage.png             Deploy stage console output
    ├── 02-verify-stage.png             Verify stage health check
    └── 03-rollback.png                 Manual rollback example
```

## Capture Instructions

1. Run the full successful pipeline
2. Capture the Jenkins Blue Ocean or Stage View screenshot
3. Run each failure scenario from `docs/failure-demos.md`
4. Capture the failing stage and console output
5. Restore and run the successful pipeline again

Screenshots can be added as PNG files in their respective subdirectories.
