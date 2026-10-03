// ─────────────────────────────────────────────────────────────────────────────
//  JenkinsForge — Container DevSecOps Pipeline
//  Repository: https://github.com/sayaksatpathi/Jenkins-DevSecOps-Pipeline
//
//  Required Jenkins credentials (configure in Manage Jenkins → Credentials):
//    ecr-registry          Secret Text  — ECR registry URL
//                                         e.g. 123456789012.dkr.ecr.us-east-1.amazonaws.com
//    aws-access-key-id     Secret Text  — AWS access key for ECR push / ECR auth
//    aws-secret-access-key Secret Text  — AWS secret key for ECR push / ECR auth
//    deploy-host           Secret Text  — Deployment target hostname or IP
//    deploy-ssh-key        SSH Username with private key — deploy user + private key
//    cosign-private-key    Secret File  — Cosign private key (cosign.key)
//    cosign-password       Secret Text  — Cosign key password
// ─────────────────────────────────────────────────────────────────────────────

pipeline {

    agent any

    environment {
        APP_NAME     = 'jenkinsforge'
        AWS_REGION   = 'us-east-1'
        ECR_REGISTRY = credentials('ecr-registry')
        DEPLOY_HOST  = credentials('deploy-host')
    }

    options {
        timestamps()
        timeout(time: 45, unit: 'MINUTES')
        buildDiscarder(logRotator(numToKeepStr: '10', artifactNumToKeepStr: '5'))
        disableConcurrentBuilds()
    }

    parameters {
        booleanParam(
            name:         'FORCE_DEPLOY',
            defaultValue: false,
            description:  'Force deployment on non-main branches (for manual testing)'
        )
        booleanParam(
            name:         'SKIP_TRIVY_BLOCKING',
            defaultValue: false,
            description:  'Treat Trivy CRITICAL findings as warnings (emergency override — use with caution)'
        )
    }

    stages {

        // ── 1. Checkout ───────────────────────────────────────────────────────
        stage('Checkout') {
            steps {
                checkout scm
                script {
                    env.GIT_SHORT_SHA    = sh(script: 'git rev-parse --short HEAD', returnStdout: true).trim()
                    env.IMAGE_TAG        = env.GIT_SHORT_SHA
                    env.FULL_IMAGE       = "${ECR_REGISTRY}/${APP_NAME}:${env.IMAGE_TAG}"
                    env.FULL_IMAGE_BUILD = "${ECR_REGISTRY}/${APP_NAME}:build-${BUILD_NUMBER}"

                    echo """
╔══════════════════════════════════════╗
║      JenkinsForge Pipeline Start     ║
╠══════════════════════════════════════╣
║ App:    ${APP_NAME}
║ Branch: ${env.BRANCH_NAME ?: 'unknown'}
║ Commit: ${env.GIT_COMMIT ?: env.GIT_SHORT_SHA}
║ Tag:    ${env.IMAGE_TAG}
║ Build:  ${BUILD_NUMBER}
║ Image:  ${env.FULL_IMAGE}
╚══════════════════════════════════════╝
"""
                }
            }
        }

        // ── 2. Unit Test ──────────────────────────────────────────────────────
        stage('Unit Test') {
            agent {
                docker {
                    image 'python:3.12-slim'
                    args  '--user root'
                    reuseNode true
                }
            }
            steps {
                dir('app') {
                    sh '''
                        pip install -r requirements-dev.txt -q
                        mkdir -p ../reports
                        pytest tests/ \
                            --junitxml=../reports/test-results.xml \
                            -v --tb=short --color=yes
                    '''
                }
            }
            post {
                always {
                    junit allowEmptyResults: false,
                          testResults:       'reports/test-results.xml'
                }
                failure {
                    echo '✗ Unit tests FAILED — pipeline will NOT proceed to deployment'
                }
                success {
                    echo '✓ Unit tests PASSED'
                }
            }
        }

        // ── 3. Lint ───────────────────────────────────────────────────────────
        stage('Lint') {
            agent {
                docker {
                    image 'python:3.12-slim'
                    args  '--user root'
                    reuseNode true
                }
            }
            steps {
                dir('app') {
                    sh '''
                        pip install ruff -q
                        echo "==> ruff: style + import checks"
                        ruff check src/ tests/
                        echo "==> ruff: format check"
                        ruff format --check src/ tests/
                        echo "✓ Lint PASSED"
                    '''
                }
            }
            post {
                failure {
                    echo '✗ Lint FAILED — fix code style errors before deploying'
                }
            }
        }

        // ── 4. SAST ───────────────────────────────────────────────────────────
        stage('SAST') {
            agent {
                docker {
                    image 'python:3.12-slim'
                    args  '--user root'
                    reuseNode true
                }
            }
            steps {
                sh '''
                    pip install semgrep -q
                    mkdir -p reports
                    echo "==> Semgrep: scanning app/src/ for security issues..."
                    semgrep scan \
                        --config p/python \
                        --config p/owasp-top-ten \
                        --config p/secrets \
                        --sarif \
                        --output reports/semgrep-results.sarif \
                        --error \
                        app/src/
                    echo "✓ SAST PASSED"
                '''
            }
            post {
                always {
                    archiveArtifacts artifacts:          'reports/semgrep-results.sarif',
                                     allowEmptyArchive:  true
                }
                failure {
                    echo '✗ SAST FAILED — security findings must be resolved before deployment'
                }
            }
        }

        // ── 5. Dependency Scan ────────────────────────────────────────────────
        stage('Dependency Scan') {
            agent {
                docker {
                    image 'python:3.12-slim'
                    args  '--user root'
                    reuseNode true
                }
            }
            steps {
                sh '''
                    pip install pip-audit -q
                    mkdir -p reports
                    echo "==> pip-audit: scanning app/requirements.txt for CVEs..."
                    pip-audit \
                        -r app/requirements.txt \
                        --format json \
                        --output reports/pip-audit-results.json \
                        --progress-spinner off
                    echo "✓ Dependency Scan PASSED — no known vulnerabilities"
                '''
            }
            post {
                always {
                    archiveArtifacts artifacts:         'reports/pip-audit-results.json',
                                     allowEmptyArchive: true
                }
                failure {
                    echo '✗ Dependency Scan FAILED — vulnerable packages must be updated before deployment'
                }
            }
        }

        // ── 6. Docker Build ───────────────────────────────────────────────────
        stage('Docker Build') {
            steps {
                sh """
                    echo "==> Building: \${FULL_IMAGE}"
                    docker build \\
                        --no-cache \\
                        --build-arg APP_VERSION=\${IMAGE_TAG} \\
                        --label "org.opencontainers.image.revision=\${GIT_COMMIT}" \\
                        --label "org.opencontainers.image.created=\$(date -u +%Y-%m-%dT%H:%M:%SZ)" \\
                        --label "jenkins.build.number=\${BUILD_NUMBER}" \\
                        -t "\${FULL_IMAGE}" \\
                        app/
                    echo "Built image ID: \$(docker image inspect \${FULL_IMAGE} --format '{{.Id}}')"
                    echo "✓ Docker Build PASSED"
                """
            }
            post {
                failure {
                    echo '✗ Docker Build FAILED'
                }
            }
        }

        // ── 7. Trivy Scan ─────────────────────────────────────────────────────
        stage('Trivy Scan') {
            steps {
                sh """
                    mkdir -p reports
                    echo "==> Trivy: scanning \${FULL_IMAGE}..."

                    # Full JSON report (archived as artifact)
                    trivy image \\
                        --format json \\
                        --output reports/trivy-results.json \\
                        --exit-code 0 \\
                        "\${FULL_IMAGE}"

                    # Human-readable summary table
                    trivy image \\
                        --format table \\
                        --output reports/trivy-table.txt \\
                        --exit-code 0 \\
                        "\${FULL_IMAGE}"

                    # Print table to console
                    cat reports/trivy-table.txt

                    echo "==> Checking for CRITICAL vulnerabilities (deployment gate)..."
                    SKIP_BLOCKING="${params.SKIP_TRIVY_BLOCKING}"
                    trivy image \\
                        --severity CRITICAL \\
                        --ignore-unfixed \\
                        --exit-code 1 \\
                        "\${FULL_IMAGE}" || {
                        if [ "\$SKIP_BLOCKING" = "true" ]; then
                            echo "WARNING: CRITICAL vulns found — SKIP_TRIVY_BLOCKING=true, continuing as warning"
                        else
                            echo "✗ CRITICAL vulnerabilities found — deployment BLOCKED"
                            exit 1
                        fi
                    }
                    echo "✓ Trivy Scan PASSED"
                """
            }
            post {
                always {
                    archiveArtifacts artifacts:         'reports/trivy-results.json,reports/trivy-table.txt',
                                     allowEmptyArchive: true
                }
                failure {
                    echo '✗ Trivy Scan FAILED — image has critical vulnerabilities, deployment prevented'
                }
            }
        }

        // ── 8. SBOM ───────────────────────────────────────────────────────────
        stage('SBOM') {
            steps {
                sh """
                    mkdir -p reports
                    echo "==> Syft: generating SBOM for \${FULL_IMAGE}..."

                    syft "\${FULL_IMAGE}" \\
                        -o cyclonedx-json=reports/sbom-cyclonedx.json \\
                        -o spdx-json=reports/sbom-spdx.json

                    COMPONENTS=\$(python3 -c "
import json
with open('reports/sbom-cyclonedx.json') as f:
    d = json.load(f)
print(len(d.get('components', [])))
")
                    echo "SBOM generated: \${COMPONENTS} components recorded"
                    echo "  - reports/sbom-cyclonedx.json (CycloneDX)"
                    echo "  - reports/sbom-spdx.json     (SPDX)"
                    echo "✓ SBOM PASSED"
                """
            }
            post {
                always {
                    archiveArtifacts artifacts:         'reports/sbom-*.json',
                                     allowEmptyArchive: true
                }
                failure {
                    echo '✗ SBOM generation FAILED'
                }
            }
        }

        // ── 9. Sign Image ─────────────────────────────────────────────────────
        stage('Sign Image') {
            environment {
                COSIGN_PASSWORD = credentials('cosign-password')
            }
            steps {
                withCredentials([
                    file(credentialsId: 'cosign-private-key', variable: 'COSIGN_KEY')
                ]) {
                    sh """
                        echo "==> Cosign: signing \${FULL_IMAGE}..."
                        cosign sign --yes \\
                            --key "\$COSIGN_KEY" \\
                            "\${FULL_IMAGE}"

                        echo "==> Cosign: verifying signature..."
                        cosign verify \\
                            --key "\$COSIGN_KEY" \\
                            "\${FULL_IMAGE}"

                        echo "✓ Image signed and signature verified"
                    """
                }
            }
            post {
                failure {
                    echo '✗ Image signing FAILED — unsigned images are never deployed'
                }
            }
        }

        // ── 10. Push to ECR ───────────────────────────────────────────────────
        stage('Push to ECR') {
            environment {
                AWS_ACCESS_KEY_ID     = credentials('aws-access-key-id')
                AWS_SECRET_ACCESS_KEY = credentials('aws-secret-access-key')
            }
            steps {
                sh """
                    echo "==> Authenticating with Amazon ECR..."
                    aws ecr get-login-password --region "\${AWS_REGION}" | \\
                        docker login --username AWS --password-stdin "\${ECR_REGISTRY}"

                    echo "==> Pushing \${FULL_IMAGE}..."
                    docker push "\${FULL_IMAGE}"

                    echo "==> Pushing build tag \${FULL_IMAGE_BUILD}..."
                    docker tag "\${FULL_IMAGE}" "\${FULL_IMAGE_BUILD}"
                    docker push "\${FULL_IMAGE_BUILD}"

                    echo "==> ECR image details:"
                    aws ecr describe-images \\
                        --repository-name "\${APP_NAME}" \\
                        --region "\${AWS_REGION}" \\
                        --image-ids imageTag="\${IMAGE_TAG}" \\
                        --query 'imageDetails[0].{Digest:imageDigest,Pushed:imagePushedAt,SizeBytes:imageSizeInBytes}' \\
                        --output table

                    echo "✓ Push to ECR PASSED"
                """
            }
            post {
                failure {
                    echo '✗ ECR push FAILED — deployment cancelled'
                }
            }
        }

        // ── 11. Deploy ────────────────────────────────────────────────────────
        stage('Deploy') {
            when {
                anyOf {
                    branch 'main'
                    expression { return params.FORCE_DEPLOY }
                }
            }
            environment {
                AWS_ACCESS_KEY_ID     = credentials('aws-access-key-id')
                AWS_SECRET_ACCESS_KEY = credentials('aws-secret-access-key')
            }
            steps {
                withCredentials([
                    sshUserPrivateKey(
                        credentialsId: 'deploy-ssh-key',
                        keyFileVariable: 'SSH_KEY',
                        usernameVariable: 'SSH_USER'
                    )
                ]) {
                    sh """
                        echo "==> Deploying \${FULL_IMAGE} to \$DEPLOY_HOST..."

                        # Get ECR auth token before SSH (token valid for 12 h)
                        ECR_PASSWORD=\$(aws ecr get-login-password --region "\${AWS_REGION}")

                        ssh -i "\$SSH_KEY" \\
                            -o StrictHostKeyChecking=no \\
                            -o ConnectTimeout=30 \\
                            "\$SSH_USER@\$DEPLOY_HOST" \\
                            "
                                set -e
                                echo '\$ECR_PASSWORD' | docker login \\
                                    --username AWS \\
                                    --password-stdin '${ECR_REGISTRY}'

                                docker pull '${FULL_IMAGE}'

                                docker stop '${APP_NAME}' 2>/dev/null || true
                                docker rm   '${APP_NAME}' 2>/dev/null || true

                                docker run -d \\
                                    --name '${APP_NAME}' \\
                                    --restart unless-stopped \\
                                    -p 8000:8000 \\
                                    -e APP_VERSION='${IMAGE_TAG}' \\
                                    -l deploy.build='${BUILD_NUMBER}' \\
                                    -l deploy.commit='${GIT_COMMIT}' \\
                                    '${FULL_IMAGE}'

                                docker ps --filter name='${APP_NAME}'
                                echo 'Deployment complete on \$(hostname)'
                            "
                        echo "✓ Deploy PASSED"
                    """
                }
            }
            post {
                failure {
                    echo '✗ Deployment FAILED'
                }
            }
        }

        // ── 12. Verify ────────────────────────────────────────────────────────
        stage('Verify') {
            when {
                anyOf {
                    branch 'main'
                    expression { return params.FORCE_DEPLOY }
                }
            }
            steps {
                sh """
                    echo "==> Waiting 15 s for container to start..."
                    sleep 15

                    echo "==> Health check: http://\$DEPLOY_HOST:8000/health"
                    HTTP_STATUS=\$(curl -sf -o /dev/null -w '%{http_code}' \\
                        --connect-timeout 10 --max-time 20 \\
                        "http://\$DEPLOY_HOST:8000/health" || echo "000")

                    if [ "\$HTTP_STATUS" != "200" ]; then
                        echo "✗ Health check returned HTTP \$HTTP_STATUS — deployment REJECTED"
                        exit 1
                    fi

                    RESPONSE=\$(curl -sf --connect-timeout 10 "http://\$DEPLOY_HOST:8000/health")
                    echo "Health response: \$RESPONSE"

                    python3 - << 'PY'
import json, sys
response = '''"\$RESPONSE"'''
d = json.loads(response.strip("'\""))
assert d.get('status') == 'healthy', f"Expected 'healthy', got: {d.get('status')}"
print(f"  service: {d['service']}")
print(f"  version: {d['version']}")
print(f"  status:  {d['status']}")
PY

                    echo ""
                    echo "✓ Verify PASSED"
                    echo "  Image:  \${FULL_IMAGE}"
                    echo "  Build:  \${BUILD_NUMBER}"
                    echo "  Commit: \${GIT_COMMIT}"
                    echo "  Host:   \$DEPLOY_HOST"
                """
            }
            post {
                failure {
                    echo '✗ Deployment verification FAILED — see docs/deployment.md for rollback instructions'
                }
                success {
                    echo "✓ Deployment of ${env.FULL_IMAGE ?: APP_NAME} verified and healthy"
                }
            }
        }

    } // end stages

    // ── Post ──────────────────────────────────────────────────────────────────
    post {
        always {
            script {
                // Local image cleanup — ignore failures
                def img = env.FULL_IMAGE ?: ''
                if (img) {
                    sh(script: "docker rmi '${img}' 2>/dev/null || true", returnStatus: true)
                }
            }
            archiveArtifacts artifacts: 'reports/**', allowEmptyArchive: true
            echo """
╔══════════════════════════════════════╗
║      JenkinsForge Pipeline End       ║
╠══════════════════════════════════════╣
║ Build:    ${BUILD_NUMBER}
║ Branch:   ${env.BRANCH_NAME ?: 'unknown'}
║ Commit:   ${env.GIT_SHORT_SHA ?: 'unknown'}
║ Result:   ${currentBuild.currentResult}
║ Duration: ${currentBuild.durationString}
╚══════════════════════════════════════╝
"""
        }
        success {
            echo 'Pipeline SUCCEEDED'
        }
        failure {
            echo 'Pipeline FAILED — check stage output above for the failing stage'
        }
        unstable {
            echo 'Pipeline UNSTABLE — some quality gates reported warnings'
        }
        cleanup {
            cleanWs notFailBuild: true
        }
    }

}
