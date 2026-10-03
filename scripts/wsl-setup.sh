#!/usr/bin/env bash
# =============================================================================
# wsl-setup.sh — Full JenkinsForge environment setup on WSL (Ubuntu)
#
# Run this script once on a fresh WSL Ubuntu instance to install:
#   Jenkins + Java 17, Docker, Trivy, Syft, Cosign, AWS CLI v2
#
# Then it walks you through:
#   - cosign key generation
#   - ECR repository creation
#   - Jenkins credential checklist
#
# Usage:
#   chmod +x scripts/wsl-setup.sh
#   ./scripts/wsl-setup.sh
# =============================================================================

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

ok()   { echo -e "${GREEN}[OK]${NC} $*"; }
info() { echo -e "${CYAN}[INFO]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
die()  { echo -e "${RED}[FAIL]${NC} $*"; exit 1; }

section() {
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}  $*${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

# =============================================================================
# 0. Preflight checks
# =============================================================================
section "0. Preflight"

# Must be Ubuntu/Debian on WSL
if ! grep -qi "ubuntu\|debian" /etc/os-release 2>/dev/null; then
    die "This script targets Ubuntu/Debian WSL. Detected: $(grep PRETTY_NAME /etc/os-release | cut -d= -f2)"
fi
ok "Ubuntu/Debian WSL detected"

# sudo must work
sudo true || die "sudo is required"
ok "sudo available"

# =============================================================================
# 1. System update
# =============================================================================
section "1. System update"

sudo apt-get update -qq
sudo apt-get upgrade -y -qq
sudo apt-get install -y -qq \
    curl wget git unzip jq ca-certificates gnupg lsb-release software-properties-common
ok "Base packages installed"

# =============================================================================
# 2. Java 17
# =============================================================================
section "2. Java 17"

if java -version 2>&1 | grep -q "version \"17"; then
    ok "Java 17 already installed"
else
    sudo apt-get install -y openjdk-17-jre
    ok "Java 17 installed"
fi
java -version 2>&1 | head -1

# =============================================================================
# 3. Docker Engine
# =============================================================================
section "3. Docker Engine"

if command -v docker &>/dev/null; then
    ok "Docker already installed: $(docker --version)"
else
    # Add Docker's official GPG key and repo
    sudo install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
        | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    sudo chmod a+r /etc/apt/keyrings/docker.gpg

    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
      https://download.docker.com/linux/ubuntu \
      $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
      | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

    sudo apt-get update -qq
    sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    ok "Docker installed"
fi

# Add current user to docker group so you don't need sudo for docker commands
if ! groups | grep -q docker; then
    sudo usermod -aG docker "$USER"
    warn "Added $USER to docker group — log out and back in (or run: newgrp docker) for it to take effect"
else
    ok "$USER already in docker group"
fi

# Start Docker daemon (WSL needs explicit start)
if ! sudo service docker status &>/dev/null; then
    sudo service docker start
fi
ok "Docker daemon running"

# =============================================================================
# 4. Jenkins
# =============================================================================
section "4. Jenkins"

if systemctl is-active --quiet jenkins 2>/dev/null || service jenkins status &>/dev/null 2>&1; then
    ok "Jenkins already running"
else
    # Add Jenkins repo
    curl -fsSL https://pkg.jenkins.io/debian-stable/jenkins.io-2023.key \
        | sudo tee /usr/share/keyrings/jenkins-keyring.asc > /dev/null
    echo "deb [signed-by=/usr/share/keyrings/jenkins-keyring.asc] \
        https://pkg.jenkins.io/debian-stable binary/" \
        | sudo tee /etc/apt/sources.list.d/jenkins.list > /dev/null

    sudo apt-get update -qq
    sudo apt-get install -y jenkins
    ok "Jenkins installed"

    # Add jenkins user to docker group so pipeline containers work
    sudo usermod -aG docker jenkins
    ok "jenkins user added to docker group"

    # Start Jenkins
    sudo service jenkins start
    ok "Jenkins service started"
fi

# Print initial admin password location
echo ""
info "Jenkins is running at: http://localhost:8080"
info "Initial admin password:"
if [ -f /var/lib/jenkins/secrets/initialAdminPassword ]; then
    echo ""
    sudo cat /var/lib/jenkins/secrets/initialAdminPassword
    echo ""
else
    warn "Password file not found yet — Jenkins may still be starting. Try:"
    echo "    sudo cat /var/lib/jenkins/secrets/initialAdminPassword"
fi

# =============================================================================
# 5. Trivy
# =============================================================================
section "5. Trivy (vulnerability scanner)"

if command -v trivy &>/dev/null; then
    ok "Trivy already installed: $(trivy --version | head -1)"
else
    curl -sfL https://raw.githubusercontent.com/aquasecurity/trivy/main/contrib/install.sh \
        | sudo sh -s -- -b /usr/local/bin
    ok "Trivy installed: $(trivy --version | head -1)"
fi

# =============================================================================
# 6. Syft
# =============================================================================
section "6. Syft (SBOM generator)"

if command -v syft &>/dev/null; then
    ok "Syft already installed: $(syft --version)"
else
    curl -sSfL https://raw.githubusercontent.com/anchore/syft/main/install.sh \
        | sudo sh -s -- -b /usr/local/bin
    ok "Syft installed: $(syft --version)"
fi

# =============================================================================
# 7. Cosign
# =============================================================================
section "7. Cosign (image signing)"

if command -v cosign &>/dev/null; then
    ok "Cosign already installed: $(cosign version 2>&1 | grep GitVersion | awk '{print $2}')"
else
    COSIGN_VERSION=$(curl -sL https://api.github.com/repos/sigstore/cosign/releases/latest \
        | grep '"tag_name":' | cut -d'"' -f4)
    sudo curl -o /usr/local/bin/cosign -sL \
        "https://github.com/sigstore/cosign/releases/download/${COSIGN_VERSION}/cosign-linux-amd64"
    sudo chmod +x /usr/local/bin/cosign
    ok "Cosign installed: $(cosign version 2>&1 | grep GitVersion | awk '{print $2}')"
fi

# =============================================================================
# 8. AWS CLI v2
# =============================================================================
section "8. AWS CLI v2"

if command -v aws &>/dev/null && aws --version 2>&1 | grep -q "aws-cli/2"; then
    ok "AWS CLI v2 already installed: $(aws --version)"
else
    curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o /tmp/awscliv2.zip
    unzip -q /tmp/awscliv2.zip -d /tmp
    sudo /tmp/aws/install --update
    rm -rf /tmp/aws /tmp/awscliv2.zip
    ok "AWS CLI v2 installed: $(aws --version)"
fi

# =============================================================================
# 9. Tool version summary
# =============================================================================
section "9. Installed tool versions"

echo ""
printf "  %-20s %s\n" "Java:"    "$(java -version 2>&1 | head -1)"
printf "  %-20s %s\n" "Docker:"  "$(docker --version)"
printf "  %-20s %s\n" "Jenkins:" "$(jenkins --version 2>/dev/null || echo 'check http://localhost:8080')"
printf "  %-20s %s\n" "Trivy:"   "$(trivy --version | head -1)"
printf "  %-20s %s\n" "Syft:"    "$(syft --version)"
printf "  %-20s %s\n" "Cosign:"  "$(cosign version 2>&1 | grep GitVersion | awk '{print $2}')"
printf "  %-20s %s\n" "AWS CLI:" "$(aws --version)"
echo ""

# =============================================================================
# 10. Cosign key generation
# =============================================================================
section "10. Cosign key generation"

KEYS_DIR="$(pwd)"
COSIGN_KEY="$KEYS_DIR/cosign.key"
COSIGN_PUB="$KEYS_DIR/cosign.pub"

if [ -f "$COSIGN_KEY" ]; then
    ok "cosign.key already exists at $COSIGN_KEY"
else
    echo ""
    warn "You need a strong passphrase for the cosign key."
    warn "You will enter it twice — remember it, you'll need it for the Jenkins credential."
    echo ""
    read -rsp "Enter cosign passphrase: " COSIGN_PASS
    echo ""
    read -rsp "Confirm passphrase: "      COSIGN_PASS2
    echo ""

    if [ "$COSIGN_PASS" != "$COSIGN_PASS2" ]; then
        die "Passphrases do not match"
    fi

    COSIGN_PASSWORD="$COSIGN_PASS" cosign generate-key-pair

    ok "Keys generated:"
    ok "  Private key: $COSIGN_KEY  ← upload to Jenkins as 'cosign-private-key' (Secret file)"
    ok "  Public  key: $COSIGN_PUB  ← safe to commit; used for verification"
    echo ""
    warn "NEVER commit cosign.key to Git. cosign.key is in .gitignore already."
    echo ""
    info "Passphrase to enter in Jenkins as 'cosign-password' credential:"
    echo "  (the passphrase you just entered — store it securely)"
fi

# =============================================================================
# 11. AWS configuration check
# =============================================================================
section "11. AWS credentials"

if aws sts get-caller-identity &>/dev/null; then
    ok "AWS credentials configured:"
    aws sts get-caller-identity --output table
else
    warn "AWS credentials not configured. Run:"
    echo ""
    echo "    aws configure"
    echo ""
    echo "  Required values:"
    echo "    AWS Access Key ID:     (from IAM user with iam/jenkins-iam-policy.json attached)"
    echo "    AWS Secret Access Key: (from the same IAM user)"
    echo "    Default region:        us-east-1"
    echo "    Default output format: json"
    echo ""
    info "Skipping ECR repository creation — configure AWS first, then rerun step 12 manually."
fi

# =============================================================================
# 12. ECR repository creation
# =============================================================================
section "12. ECR repository"

if aws sts get-caller-identity &>/dev/null; then
    AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    ECR_URI="${AWS_ACCOUNT_ID}.dkr.ecr.us-east-1.amazonaws.com"

    if aws ecr describe-repositories --repository-names jenkinsforge --region us-east-1 &>/dev/null; then
        ok "ECR repository 'jenkinsforge' already exists"
    else
        aws ecr create-repository \
            --repository-name jenkinsforge \
            --region us-east-1 \
            --image-scanning-configuration scanOnPush=true \
            --image-tag-mutability IMMUTABLE \
            --encryption-configuration encryptionType=AES256
        ok "ECR repository created: $ECR_URI/jenkinsforge"

        # Apply lifecycle policy
        if [ -f iam/ecr-lifecycle-policy.json ]; then
            aws ecr put-lifecycle-policy \
                --repository-name jenkinsforge \
                --region us-east-1 \
                --lifecycle-policy-text file://iam/ecr-lifecycle-policy.json
            ok "ECR lifecycle policy applied"
        fi
    fi

    echo ""
    info "ECR registry URL for Jenkins 'ecr-registry' credential:"
    echo "  ${ECR_URI}"
fi

# =============================================================================
# 13. Jenkins credentials checklist
# =============================================================================
section "13. Jenkins credentials checklist"

echo ""
echo "  Open: http://localhost:8080/manage/credentials/store/system/domain/_/"
echo "  Add each credential with the exact ID shown."
echo ""
echo "  ┌──────────────────────────┬─────────────────────┬──────────────────────────────────────────┐"
echo "  │ Credential ID            │ Kind                │ Value                                    │"
echo "  ├──────────────────────────┼─────────────────────┼──────────────────────────────────────────┤"
echo "  │ ecr-registry             │ Secret text         │ <account>.dkr.ecr.us-east-1.amazonaws.com│"
echo "  │ aws-access-key-id        │ Secret text         │ Your IAM access key ID                   │"
echo "  │ aws-secret-access-key    │ Secret text         │ Your IAM secret access key               │"
echo "  │ deploy-host              │ Secret text         │ EC2 IP or hostname for deployment         │"
echo "  │ deploy-ssh-key           │ SSH Username+key    │ ec2-user / paste PEM private key          │"
echo "  │ cosign-private-key       │ Secret file         │ Upload ./cosign.key                      │"
echo "  │ cosign-password          │ Secret text         │ Passphrase from step 10                  │"
echo "  └──────────────────────────┴─────────────────────┴──────────────────────────────────────────┘"
echo ""

# =============================================================================
# 14. Jenkins plugins checklist
# =============================================================================
section "14. Jenkins plugins to install"

echo ""
echo "  Manage Jenkins → Plugins → Available → search and install:"
echo ""
echo "    Pipeline"
echo "    Pipeline: Declarative"
echo "    Git"
echo "    GitHub Integration"
echo "    Credentials Binding"
echo "    Docker Pipeline"
echo "    JUnit"
echo "    SSH Agent"
echo ""
echo "  Then: Manage Jenkins → Restart"
echo ""

# =============================================================================
# 15. Pipeline job setup
# =============================================================================
section "15. Pipeline job"

echo ""
echo "  1. New Item → Pipeline"
echo "  2. Name: jenkinsforge"
echo "  3. Pipeline → Pipeline script from SCM"
echo "       SCM: Git"
echo "       Repository URL: https://github.com/sayaksatpathi/Jenkins-DevSecOps-Pipeline"
echo "       Branch: */main"
echo "       Script Path: Jenkinsfile"
echo "  4. Build Triggers → GitHub hook trigger for GITScm polling"
echo "  5. Save → Build Now"
echo ""

# =============================================================================
# Done
# =============================================================================
section "Setup complete"

echo ""
ok "All tools installed."
echo ""
echo "  Next steps:"
echo "    1. Open Jenkins:        http://localhost:8080"
echo "    2. Complete initial setup wizard and install plugins (step 14)"
echo "    3. Add all 7 credentials (step 13)"
echo "    4. Create the pipeline job (step 15)"
echo "    5. Trigger a build and watch all 12 stages go green"
echo ""
if [ -f cosign.key ]; then
    echo -e "  ${YELLOW}Remember: cosign.key is in this directory. Upload it to Jenkins, then delete the local copy.${NC}"
fi
echo ""
