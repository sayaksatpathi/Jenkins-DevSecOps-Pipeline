# Troubleshooting

## Pipeline Issues

### "docker: command not found" in a stage

The Jenkins agent does not have Docker installed or the `jenkins` user is not in the `docker` group.

```bash
# On the Jenkins host
sudo usermod -aG docker jenkins
sudo systemctl restart jenkins
```

### Docker agent stage fails: "Cannot connect to Docker daemon"

The Docker Pipeline plugin needs access to the Docker socket.

Check the Jenkins Docker agent configuration and ensure `/var/run/docker.sock` is accessible.

```bash
ls -la /var/run/docker.sock
sudo chmod 666 /var/run/docker.sock   # temporary fix
```

For a permanent fix, ensure Jenkins is in the docker group (see above).

### "trivy: command not found"

Trivy must be installed on the Jenkins agent (not inside a container).

```bash
curl -sfL https://raw.githubusercontent.com/aquasecurity/trivy/main/contrib/install.sh | \
    sudo sh -s -- -b /usr/local/bin
trivy --version
```

### "syft: command not found"

```bash
curl -sSfL https://raw.githubusercontent.com/anchore/syft/main/install.sh | \
    sudo sh -s -- -b /usr/local/bin
syft --version
```

### "cosign: command not found"

```bash
COSIGN_VERSION=$(curl -sL https://api.github.com/repos/sigstore/cosign/releases/latest \
    | grep '"tag_name":' | cut -d'"' -f4)
sudo curl -o /usr/local/bin/cosign -sL \
    "https://github.com/sigstore/cosign/releases/download/${COSIGN_VERSION}/cosign-linux-amd64"
sudo chmod +x /usr/local/bin/cosign
cosign version
```

---

## ECR / AWS Issues

### "Error: An error occurred (AuthFailure) when calling the GetAuthorizationToken operation"

The `aws-access-key-id` or `aws-secret-access-key` credentials in Jenkins are incorrect or expired.

1. Verify IAM credentials in AWS Console
2. Update the Jenkins credentials

### "Error: name unknown: The repository with name 'jenkinsforge' does not exist"

Create the ECR repository first:

```bash
aws ecr create-repository \
    --repository-name jenkinsforge \
    --region us-east-1 \
    --image-tag-mutability IMMUTABLE
```

### "Error: tag invalid: The image tag 'abc123' already exists in the repository and cannot be overwritten"

This is correct behavior — ECR immutable tags prevent overwriting.
This error means a build with the same git SHA has already been pushed.
This should not happen if commits are unique (they always are).

---

## Signing Issues

### "cosign: error loading key: cosign.key: failed to decrypt"

The `cosign-password` credential does not match the passphrase used to generate the key.

Re-generate the key pair with a known passphrase and upload both credentials:

```bash
COSIGN_PASSWORD="<new-passphrase>" cosign generate-key-pair
# Upload cosign.key → Jenkins Secret file credential 'cosign-private-key'
# Set <new-passphrase> → Jenkins Secret text credential 'cosign-password'
```

---

## Application Issues

### Health check returns HTTP 000 (connection refused)

The container is not running or not listening on port 8000.

```bash
# On the deployment host
docker ps --filter name=jenkinsforge
docker logs jenkinsforge --tail=50
```

### Health check returns `"status": "ok"` but Verify fails

The health endpoint returns `"status": "ok"` on `GET /`, not `"status": "healthy"`.
The Verify stage checks the `/health` endpoint specifically.

Ensure you are calling `http://<host>:8000/health` not `http://<host>:8000/`.

---

## Webhook Issues

### Jenkins not triggering on push

1. Check GitHub → Repository → Settings → Webhooks → Recent Deliveries
2. Verify the webhook URL is reachable from GitHub's IP ranges
3. Check Jenkins logs: **Manage Jenkins → System Log**
4. Verify the GitHub Integration Plugin is installed and configured

### "403 No valid crumb" on webhook

CSRF protection may be blocking the webhook. Configure the GitHub Plugin to use
the proper authentication method, or ensure the webhook URL uses `/github-webhook/` not `/build`.

---

## Semgrep Issues

### "semgrep: Permission denied" or semgrep times out

Running semgrep in the Docker agent container:

- Ensure the container has network access to pull rule sets (`p/python`, etc.)
- For air-gapped environments, pre-download rules and use `--config <local-path>`

### Semgrep reports false positives

Add a `# nosemgrep` comment to suppress a specific finding after review:

```python
INTERNAL_KEY = os.environ["INTERNAL_KEY"]  # nosemgrep: generic.secrets.security
```

Document each suppression in a comment explaining why it is safe.

---

## pip-audit Issues

### "No vulnerabilities found" when there should be

pip-audit queries the [OSV vulnerability database](https://osv.dev).
If the database has not been updated, new CVEs may not appear immediately.

Run `pip-audit --list` to verify connectivity.

### pip-audit fails for a package with no known CVEs

This is expected and correct — the stage only fails when actual vulnerabilities are found.
