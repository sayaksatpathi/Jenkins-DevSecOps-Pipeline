#!/usr/bin/env bash
# Issues an access key for the least-privilege IAM user (iam/jenkins-iam-policy.json)
# and stores it straight into Jenkins as 'aws-access-key-id' / 'aws-secret-access-key'.
# The secret is never printed, never on a command line, and never left on disk.
# Re-running rotates the key: the new one is verified before old ones are deleted.
#
# Run as a user whose AWS CLI may manage IAM:
#   scripts/setup-jenkins-aws-credentials.sh
# Optional env: CI_USER (jenkinsforge-ci), JENKINS_URL (http://localhost:8080),
#               JENKINS_USER (admin), JENKINS_PASSWORD (prompted if unset)
set -euo pipefail

CI_USER="${CI_USER:-jenkinsforge-ci}"
REGION="${AWS_REGION:-us-east-1}"
JENKINS_URL="${JENKINS_URL:-http://localhost:8080}"
JENKINS_USER="${JENKINS_USER:-admin}"

if [ -z "${JENKINS_PASSWORD:-}" ]; then
    read -r -s -p "Jenkins password for '$JENKINS_USER' at $JENKINS_URL: " JENKINS_PASSWORD
    echo
fi

umask 077
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
printf 'user = "%s:%s"\n' "$JENKINS_USER" "$JENKINS_PASSWORD" > "$TMP/curl.cfg"
unset JENKINS_PASSWORD

CRUMB="$(curl -sf -K "$TMP/curl.cfg" -c "$TMP/cookies" "$JENKINS_URL/crumbIssuer/api/json" \
    | python3 -c 'import sys, json; print(json.load(sys.stdin)["crumb"])')" \
    || { echo "✗ Could not log in to Jenkins at $JENKINS_URL" >&2; exit 1; }
echo "✓ Jenkins login OK"

aws iam get-user --user-name "$CI_USER" >/dev/null \
    || { echo "✗ IAM user '$CI_USER' not found — create it first (see docs/jenkins-setup.md)" >&2; exit 1; }

echo "==> Creating a new access key for IAM user '$CI_USER'"
aws iam create-access-key --user-name "$CI_USER" --output json > "$TMP/key.json"
NEW_ID="$(python3 -c 'import sys, json; print(json.load(open(sys.argv[1]))["AccessKey"]["AccessKeyId"])' "$TMP/key.json")"
echo "    new key id: $NEW_ID (secret not shown)"

python3 - "$TMP/key.json" > "$TMP/upsert.groovy" <<'PY'
import base64, json, sys
k = json.load(open(sys.argv[1]))["AccessKey"]
b64 = lambda s: base64.b64encode(s.encode()).decode()
print(f"""
import com.cloudbees.plugins.credentials.CredentialsScope
import com.cloudbees.plugins.credentials.SystemCredentialsProvider
import com.cloudbees.plugins.credentials.domains.Domain
import org.jenkinsci.plugins.plaincredentials.impl.StringCredentialsImpl
import hudson.util.Secret

def store  = SystemCredentialsProvider.getInstance().getStore()
def domain = Domain.global()
def dec    = {{ s -> new String(java.util.Base64.decoder.decode(s), 'UTF-8') }}
[
    'aws-access-key-id'    : ['AWS access key id ({k["UserName"]})',     dec('{b64(k["AccessKeyId"])}')],
    'aws-secret-access-key': ['AWS secret access key ({k["UserName"]})', dec('{b64(k["SecretAccessKey"])}')],
].each {{ id, v ->
    def old = store.getCredentials(domain).find {{ it.id == id }}
    if (old) {{ store.removeCredentials(domain, old) }}
    store.addCredentials(domain, new StringCredentialsImpl(CredentialsScope.GLOBAL, id, v[0], Secret.fromString(v[1])))
    println "    stored Jenkins credential '${{id}}'"
}}
""")
PY

echo "==> Storing the key in Jenkins"
curl -sf -K "$TMP/curl.cfg" -b "$TMP/cookies" -H "Jenkins-Crumb: $CRUMB" \
    --data-urlencode "script@$TMP/upsert.groovy" "$JENKINS_URL/scriptText"

echo "==> Verifying the new key can reach ECR (IAM keys take a few seconds to propagate)"
export AWS_ACCESS_KEY_ID="$NEW_ID"
AWS_SECRET_ACCESS_KEY="$(python3 -c 'import sys, json; print(json.load(open(sys.argv[1]))["AccessKey"]["SecretAccessKey"])' "$TMP/key.json")"
export AWS_SECRET_ACCESS_KEY
rm -f "$TMP/key.json" "$TMP/upsert.groovy"
for i in $(seq 1 12); do
    if aws ecr describe-repositories --region "$REGION" --repository-names jenkinsforge \
           --query 'repositories[0].repositoryUri' --output text 2>/dev/null; then
        VERIFIED=1; break
    fi
    sleep 5
done
unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY
[ "${VERIFIED:-0}" = 1 ] || { echo "✗ New key could not reach ECR — old keys were left in place" >&2; exit 1; }
echo "✓ New key works"

for old in $(aws iam list-access-keys --user-name "$CI_USER" --query 'AccessKeyMetadata[].AccessKeyId' --output text); do
    if [ "$old" != "$NEW_ID" ]; then
        aws iam delete-access-key --user-name "$CI_USER" --access-key-id "$old"
        echo "    deleted previous key $old"
    fi
done

echo "✓ Done — Jenkins now holds a working, least-privilege AWS key for '$CI_USER'"
