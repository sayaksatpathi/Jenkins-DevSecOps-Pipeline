# Jenkins Setup Guide

Complete setup instructions from a clean EC2 instance.

---

## 1. Prerequisites

| Requirement           | Minimum version  |
|-----------------------|------------------|
| Jenkins               | 2.440+           |
| Java                  | 17               |
| Docker Engine         | 24+              |
| Trivy                 | 0.50+            |
| Syft                  | 1.0+             |
| Cosign                | 2.2+             |
| AWS CLI               | 2.x              |

---

## 2. Jenkins Installation (Amazon Linux 2023 / Ubuntu)

```bash
# Amazon Linux 2023
sudo dnf install java-17-amazon-corretto -y
sudo wget -O /etc/yum.repos.d/jenkins.repo https://pkg.jenkins.io/redhat-stable/jenkins.repo
sudo rpm --import https://pkg.jenkins.io/redhat-stable/jenkins.io-2023.key
sudo dnf install jenkins -y
sudo systemctl enable --now jenkins

# Ubuntu 22.04
sudo apt-get install -y openjdk-17-jre
curl -fsSL https://pkg.jenkins.io/debian-stable/jenkins.io-2023.key | sudo tee /usr/share/keyrings/jenkins-keyring.asc > /dev/null
echo "deb [signed-by=/usr/share/keyrings/jenkins-keyring.asc] https://pkg.jenkins.io/debian-stable binary/" | sudo tee /etc/apt/sources.list.d/jenkins.list
sudo apt-get update && sudo apt-get install jenkins -y
```

### Add Jenkins to docker group

```bash
sudo usermod -aG docker jenkins
sudo systemctl restart jenkins
```

---

## 3. Security Scanning Tools Installation

```bash
# Trivy
curl -sfL https://raw.githubusercontent.com/aquasecurity/trivy/main/contrib/install.sh | sudo sh -s -- -b /usr/local/bin

# Syft (SBOM generator)
curl -sSfL https://raw.githubusercontent.com/anchore/syft/main/install.sh | sudo sh -s -- -b /usr/local/bin

# Cosign (image signing)
COSIGN_VERSION=$(curl -sL https://api.github.com/repos/sigstore/cosign/releases/latest | grep '"tag_name":' | cut -d'"' -f4)
sudo curl -o /usr/local/bin/cosign -sL "https://github.com/sigstore/cosign/releases/download/${COSIGN_VERSION}/cosign-linux-amd64"
sudo chmod +x /usr/local/bin/cosign

# AWS CLI v2
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o /tmp/awscliv2.zip
unzip /tmp/awscliv2.zip -d /tmp
sudo /tmp/aws/install
```

---

## 4. Required Jenkins Plugins

Install via **Manage Jenkins → Plugins → Available**:

| Plugin                          | Purpose                                  |
|---------------------------------|------------------------------------------|
| `Pipeline`                      | Declarative pipeline syntax              |
| `Pipeline: Declarative`         | Declarative pipeline support             |
| `Git`                           | Git checkout                             |
| `GitHub Integration`            | Webhook processing and PR status         |
| `Credentials`                   | Secret storage                           |
| `Credentials Binding`           | Secret injection into build steps        |
| `Docker Pipeline`               | `agent { docker { ... } }` syntax        |
| `JUnit`                         | Test result publishing                   |
| `SSH Agent`                     | SSH key injection for deployment         |
| `Multibranch Scan Webhook Trigger` | (Optional) Webhook for multibranch   |

---

## 5. Credentials Configuration

Navigate to **Manage Jenkins → Credentials → System → Global credentials → Add Credential**.

Create the following credentials **exactly** (IDs are referenced in the Jenkinsfile):

### ecr-registry
- **Kind:** Secret text
- **ID:** `ecr-registry`
- **Secret:** `<account-id>.dkr.ecr.<region>.amazonaws.com`
  (e.g. `123456789012.dkr.ecr.us-east-1.amazonaws.com`)

### aws-access-key-id
- **Kind:** Secret text
- **ID:** `aws-access-key-id`
- **Secret:** AWS IAM access key ID (see `iam/jenkins-iam-policy.json`)

### aws-secret-access-key
- **Kind:** Secret text
- **ID:** `aws-secret-access-key`
- **Secret:** AWS IAM secret access key

### deploy-host
- **Kind:** Secret text
- **ID:** `deploy-host`
- **Secret:** Deployment EC2 hostname or IP address

### deploy-ssh-key
- **Kind:** SSH Username with private key
- **ID:** `deploy-ssh-key`
- **Username:** `ec2-user` (or the appropriate SSH user)
- **Private Key:** Enter directly — paste the PEM private key

### cosign-private-key
- **Kind:** Secret file
- **ID:** `cosign-private-key`
- **File:** Upload `cosign.key` (generated with `cosign generate-key-pair`)

### cosign-password
- **Kind:** Secret text
- **ID:** `cosign-password`
- **Secret:** Passphrase used when generating the cosign key pair

---

## 6. Cosign Key Generation

Run on a secure workstation (not the Jenkins server):

```bash
# Generate key pair — keep cosign.key private, publish cosign.pub
COSIGN_PASSWORD=<strong-passphrase> cosign generate-key-pair

# cosign.key  → upload to Jenkins as 'cosign-private-key' Secret file
# cosign.pub  → commit to the repository (public verification key)
```

**Never commit `cosign.key` to Git.**

---

## 7. Pipeline Job Configuration

### Option A: Multibranch Pipeline (Recommended)

1. **New Item → Multibranch Pipeline**
2. Name: `jenkinsforge`
3. **Branch Sources → GitHub**
   - Repository: `https://github.com/sayaksatpathi/Jenkins-DevSecOps-Pipeline`
   - Scan credentials: GitHub Personal Access Token (see credentials)
4. **Build Configuration → by Jenkinsfile**
   - Script Path: `Jenkinsfile`
5. **Scan Multibranch Pipeline Triggers → Periodically if not otherwise run:** 1 minute
   (webhook replaces the need for polling — see section 8)
6. Save

### Option B: Pipeline Job (Simpler)

1. **New Item → Pipeline**
2. Name: `jenkinsforge`
3. Pipeline → **Pipeline script from SCM**
   - SCM: Git
   - Repository: `https://github.com/sayaksatpathi/Jenkins-DevSecOps-Pipeline`
   - Branch: `*/main`
   - Script Path: `Jenkinsfile`
4. **Build Triggers → GitHub hook trigger for GITScm polling**
5. Save

---

## 8. GitHub Webhook Setup

### 8.1 Get Jenkins URL

Jenkins must be publicly reachable from GitHub.

```
http://<jenkins-host>:8080/github-webhook/
```

For HTTPS (recommended):
```
https://<jenkins-host>/github-webhook/
```

### 8.2 Configure Webhook on GitHub

1. GitHub repository → **Settings → Webhooks → Add webhook**
2. **Payload URL:** `https://<jenkins-host>/github-webhook/`
3. **Content type:** `application/json`
4. **Secret:** Generate a strong random secret and save it
5. **Events:** Select **Pushes** and **Pull requests**
6. Click **Add webhook**

### 8.3 Configure Webhook Secret in Jenkins

If using the GitHub Plugin with secret validation:
1. **Manage Jenkins → Configure System → GitHub**
2. Add GitHub Server, configure the webhook secret

---

## 9. ECR Repository Creation

```bash
aws ecr create-repository \
    --repository-name jenkinsforge \
    --region us-east-1 \
    --image-scanning-configuration scanOnPush=true \
    --image-tag-mutability IMMUTABLE \
    --encryption-configuration encryptionType=AES256
```

Apply the lifecycle policy to limit stored images:

```bash
aws ecr put-lifecycle-policy \
    --repository-name jenkinsforge \
    --region us-east-1 \
    --lifecycle-policy-text file://iam/ecr-lifecycle-policy.json
```

---

## 10. Deployment EC2 Host Setup

The deployment target needs Docker installed and the Jenkins SSH public key authorized:

```bash
# On the deployment EC2 host:
sudo dnf install docker -y
sudo systemctl enable --now docker
sudo usermod -aG docker ec2-user

# Authorize the Jenkins deploy SSH key
mkdir -p ~/.ssh && chmod 700 ~/.ssh
echo "<jenkins-deploy-public-key>" >> ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys
```

---

## 11. Verify End-to-End

1. Push a commit to `main`
2. Watch Jenkins trigger automatically (or click **Scan Multibranch Pipeline Now**)
3. Confirm all 12 stages pass
4. Verify the health endpoint responds from the deployment host
5. Check ECR for the pushed image

```bash
# Confirm deployment
curl http://<deploy-host>:8000/health

# Confirm ECR image
aws ecr describe-images \
    --repository-name jenkinsforge \
    --region us-east-1 \
    --query 'imageDetails[*].{Tag:imageTags[0],Digest:imageDigest,Pushed:imagePushedAt}' \
    --output table
```
