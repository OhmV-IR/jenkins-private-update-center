#!/bin/sh
set -eu

DATA_DIR="${DATA_DIR:-/var/lib/update-center}"
SIGNING_DIR="$DATA_DIR/signing"
export UPDATE_CENTER_URL="${UPDATE_CENTER_URL:-http://localhost:8089}"

: "${NEXUS_URL:?NEXUS_URL must be set}"
: "${NEXUS_USER:?NEXUS_USER must be set}"
: "${NEXUS_PASS:?NEXUS_PASS must be set}"

mkdir -p "$DATA_DIR/www" "$DATA_DIR/cache" "$SIGNING_DIR"

# Jenkins only accepts signed update sites. Generate a long-lived self-signed
# certificate on first start and keep it in the data volume; Jenkins trusts it
# once update-center.crt is copied to $JENKINS_HOME/update-center-rootCAs/.
if [ ! -s "$SIGNING_DIR/update-center.key" ] || [ ! -s "$SIGNING_DIR/update-center.crt" ]; then
  echo "Generating update site signing certificate in ${SIGNING_DIR}..."
  openssl req -x509 -newkey rsa:4096 -sha256 -nodes -days 3650 \
    -subj "/CN=${UPDATE_CENTER_ID:-ohmvir-nexus} update center" \
    -keyout "$SIGNING_DIR/update-center.key" \
    -out "$SIGNING_DIR/update-center.crt" 2>/dev/null
  chmod 600 "$SIGNING_DIR/update-center.key"
fi
cp "$SIGNING_DIR/update-center.crt" "$DATA_DIR/www/update-center.crt"

# busybox crond starts jobs with an empty environment, so save ours for them.
export -p | grep -E '^export (NEXUS_|CF_ACCESS_|UPDATE_CENTER_|GITHUB_|PLUGIN_MAINTAINER_|DATA_DIR=)' > /etc/update-center.env
chmod 600 /etc/update-center.env

python3 -u /usr/local/bin/nexus-artifactory-proxy.py &
for attempt in $(seq 1 15); do
  wget -qO- http://127.0.0.1:8765/healthz >/dev/null 2>&1 && break
  sleep 1
done

/usr/local/bin/sync-center.sh || echo "Initial update-center generation failed; nginx will still start."
crond -b -l 2
exec nginx -g "daemon off;"
