# Local stand-in for the remote deployment host: its own Docker engine (DinD),
# reachable only over SSH with key auth — the same contract an EC2 host offers
# the Deploy stage, without paying for one.
#
#   docker build -t jenkinsforge-deploy-target \
#       --build-arg DEPLOY_PUBKEY="$(cat deploy_ed25519.pub)" local-deploy-target/
#   docker network create jenkinsforge-net
#   docker run -d --name jf-deploy-target --privileged --network jenkinsforge-net \
#       --restart unless-stopped -p 8001:8000 \
#       -v jf-deploy-docker:/var/lib/docker jenkinsforge-deploy-target
#   docker network connect jenkinsforge-net jenkins
FROM docker:27-dind

ARG DEPLOY_PUBKEY

RUN apk upgrade --no-cache \
 && apk add --no-cache openssh-server openssh-keygen \
 && ssh-keygen -A \
 && (getent group docker || addgroup -S docker) \
 && adduser -D -s /bin/sh -G docker deploy \
 && echo 'deploy:*' | chpasswd -e \
 && printf '%s\n' \
      'PasswordAuthentication no' \
      'KbdInteractiveAuthentication no' \
      'PermitRootLogin no' \
      'AllowUsers deploy' >> /etc/ssh/sshd_config \
 && test -n "$DEPLOY_PUBKEY" \
 && install -d -m 700 -o deploy -g docker /home/deploy/.ssh \
 && echo "$DEPLOY_PUBKEY" > /home/deploy/.ssh/authorized_keys \
 && chown deploy:docker /home/deploy/.ssh/authorized_keys \
 && chmod 600 /home/deploy/.ssh/authorized_keys

COPY entrypoint.sh /usr/local/bin/deploy-target-entrypoint.sh
RUN sed -i 's/\r$//' /usr/local/bin/deploy-target-entrypoint.sh \
 && chmod +x /usr/local/bin/deploy-target-entrypoint.sh

EXPOSE 22 8000
ENTRYPOINT ["deploy-target-entrypoint.sh"]
# Socket group lets the non-root 'deploy' user drive the inner Docker engine
CMD ["--group", "docker"]
