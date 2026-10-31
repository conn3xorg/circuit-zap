# Local example

Applies circuit-zap to a throwaway Rocky Linux 10 container with systemd. The only thing it scans is a deliberately weak page that `check.sh` starts inside that same container. You need Conn3x and Podman.

ZAP runs under Podman inside that container, so the host container is privileged, which is simplest with rootful Podman. On a Mac, use the Podman machine's root connection. On Linux, use `sudo podman`:

```sh
export CONTAINER_CONNECTION=podman-machine-default-root   # macOS
export PODMAN="sudo podman"                               # Linux
./up.sh
conn3x init
conn3x apply
conn3x plan
```

The second plan says `No changes.` The apply sets up the weekly timer but doesn't scan, and the page isn't running yet. To start the page, scan it through the timer's service and check the report:

```sh
podman exec -i circuit-zap sh -s http://10.89.0.250:8099/ passive < check.sh
```

It prints the alert counts and passes if the report names `Content Security Policy (CSP) Header Not Set`, rule 10038, and the page's access log shows no attack payloads. To read the report:

```sh
ssh -p 2222 -i id_ed25519 -o UserKnownHostsFile=known_hosts root@127.0.0.1 'cat /var/lib/conn3x-zap/latest/*.md'
```

To watch the difference an active scan makes, turn it on and check again. Now the access log has to show attack payloads:

```sh
conn3x apply -var active_scan=true
podman exec -i circuit-zap sh -s http://10.89.0.250:8099/ active < check.sh
```

`up.sh` listens on `127.0.0.1:2222`. Set `PORT` to use another port, and pass the same port to Conn3x with `-var port=PORT`. Set `CONTAINERFILE` to test another distro, such as one of the images in Conn3x's `test/images`, which CI uses.

`./down.sh` stops the container, which removes it and its volume, and deletes the key and the state.
