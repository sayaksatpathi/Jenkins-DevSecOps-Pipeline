#!/bin/sh
set -e
/usr/sbin/sshd -e
exec dockerd-entrypoint.sh "$@"
