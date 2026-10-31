#!/usr/bin/env sh
# Runs on the host: starts a deliberately weak page in a container of its own,
# scans it through the timer's service, and checks that the report names a
# finding the page was built to have. The page's access log then says whether
# the scan attacked it. CI pipes this in with podman exec.
# Usage: sh check.sh TARGET_URL [passive|active]
set -eu
target=$1
mode=${2:-passive}
ip=$(printf '%s' "$target" | sed -n 's|^http://\([0-9.]*\):8099/$|\1|p')
[ -n "$ip" ] || { echo "Expected a target like http://10.89.0.250:8099/." >&2; exit 1; }
systemctl is-enabled conn3x-zap.timer

# ZAP's image brings Python. The page has a login form and none of the headers
# a page should send, and http.server sends none of them.
image=$(sed -n 's|^ *\(ghcr.io/zaproxy/zaproxy:[^ ]*\).*|\1|p' /usr/local/sbin/conn3x-zap | head -n 1)
page='<!doctype html><title>weak</title><form action="/" method="get"><input name="q"><input type="password" name="p"><input type="submit"></form>'
cid=$(podman run -d --rm --ip "$ip" --entrypoint sh "$image" -c "mkdir -p /tmp/page && cd /tmp/page && echo '$page' > index.html && exec timeout 3600 python3 -u -m http.server 8099")
trap 'podman stop -t 2 "$cid" >/dev/null 2>&1 || true' EXIT
sleep 2

systemctl start conn3x-zap.service

d=/var/lib/conn3x-zap/latest
cat "$d/summary.txt"
name=$(printf '%s' "$target" | sed 's/[^A-Za-z0-9][^A-Za-z0-9]*/_/g; s/^_//; s/_$//')
# ZAP rule 10038. http.server sends no Content-Security-Policy.
grep -q 'Content Security Policy (CSP) Header Not Set' "$d/$name.json"
grep -q '"pluginid": *"10038"' "$d/$name.json"
[ -s "$d/$name.html" ]
[ -s "$d/$name.md" ]

# Payloads in the access log mean an attack: active rules try these, and a
# spider has no reason to.
log=$(podman logs "$cid" 2>&1)
attacks=$(printf '%s\n' "$log" | grep -cE 'etc/passwd|\.\./|<script|%3Cscript|%27|OR%201|WEB-INF' || true)
echo "Requests to the page: $(printf '%s\n' "$log" | grep -c HTTP/ || true), with attack payloads: $attacks"
case "$mode" in
  passive) [ "$attacks" = 0 ] || { echo "A passive scan sent attack payloads." >&2; exit 1; } ;;
  active) [ "$attacks" -gt 0 ] || { echo "An active scan sent no attack payloads." >&2; exit 1; } ;;
esac
echo "All checks passed."
