#!/usr/bin/env bash
set -euo pipefail

mkdir -p /run/sshd /root/.ssh

if [ -d /host-ssh ]; then
  find /host-ssh -maxdepth 1 -type f \( -name 'id_*' -o -name 'config' -o -name 'known_hosts' \) \
    -exec cp {} /root/.ssh/ \;
fi

if [ -f /tmp/authorized_keys.pub ]; then
  cat /tmp/authorized_keys.pub >> /root/.ssh/authorized_keys
fi

chmod 700 /root/.ssh
find /root/.ssh -type f -exec chmod 600 {} \;
chmod 644 /root/.ssh/authorized_keys 2>/dev/null || true

exec /usr/sbin/sshd -D -e
