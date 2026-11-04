#!/usr/bin/env sh
# Starts a throwaway host on 127.0.0.1:$PORT (default 2222) that Conn3x can
# configure, with a fresh SSH key and its host key in ./known_hosts.
# CONTAINERFILE picks another image, such as one of Conn3x's test images.
# Needs Podman, since the host runs systemd. Podman inside runs containers of
# its own, so the host container is privileged and keeps /var/lib/containers on
# a volume, where the inner Podman can use overlayfs. It also lifts Podman's limit
# of 2048 tasks: systemd inside gives each service 15% of that, and an active
# scan needs more. That's only for this nested setup; a real host needs none of it.
# Rootful Podman is simplest: CONTAINER_CONNECTION=podman-machine-default-root
# on a Mac, or PODMAN="sudo podman" on Linux.
set -eu
cd "$(dirname "$0")"
port=${PORT:-2222}
containerfile=${CONTAINERFILE:-Containerfile}
name=${CONTAINER_NAME:-circuit-zap}

podman=${PODMAN:-podman}
[ -f id_ed25519 ] || ssh-keygen -q -t ed25519 -N '' -C "$name" -f id_ed25519
$podman build -q -f "$containerfile" -t "$name" "$(dirname "$containerfile")" >/dev/null
# --rm takes the container and its volume away when down.sh stops it. If the
# name is still in use, this fails rather than replacing someone's container.
$podman run -d --rm --name "$name" --systemd=always --privileged --pids-limit=-1 -v /var/lib/containers \
  -p "127.0.0.1:$port:22" "$name" > .container-id
$podman exec -i "$name" sh -c 'cat > /root/.ssh/authorized_keys && chmod 600 /root/.ssh/authorized_keys' < id_ed25519.pub
# The outer and inner Podman would both put their bridge on 10.88.0.0/16, so
# the inner one gets another subnet.
$podman exec "$name" sh -c 'mkdir -p /etc/containers/containers.conf.d && printf "[network]\ndefault_subnet = \"10.89.0.0/16\"\n" > /etc/containers/containers.conf.d/50-nested.conf'
$podman exec "$name" timeout 60 systemctl is-system-running --wait >/dev/null 2>&1 || true

for _ in 1 2 3 4 5 6 7 8 9 10; do
  if ssh-keyscan -p "$port" 127.0.0.1 > known_hosts 2>/dev/null && [ -s known_hosts ]; then
    echo "Ready on 127.0.0.1:$port. Now run: conn3x init && conn3x apply -var port=$port"
    exit 0
  fi
  sleep 1
done
echo "The container started, but SSH didn't answer on 127.0.0.1:$port." >&2
exit 1
