#!/usr/bin/env sh
# Stops the container up.sh started, which removes it and its volume, and
# deletes everything up.sh and Conn3x created here.
set -eu
cd "$(dirname "$0")"
if [ -f .container-id ]; then
  ${PODMAN:-podman} stop -t 5 "$(cat .container-id)" >/dev/null 2>&1 || true
fi
rm -rf .container-id id_ed25519 id_ed25519.pub known_hosts .terraform .terraform.lock.hcl terraform.tfstate terraform.tfstate.backup
echo "Removed."
