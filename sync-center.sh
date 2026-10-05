#!/bin/bash
set -euo pipefail

# Configuration
NEXUS_URL="${NEXUS_URL:?NEXUS_URL must be set}"
NEXUS_USER="${NEXUS_USER:?NEXUS_USER must be set}"
NEXUS_PASS="${NEXUS_PASS:?NEXUS_PASS must be set}"
UPDATE_CENTER_URL="${UPDATE_CENTER_URL:?UPDATE_CENTER_URL must be set to the URL Jenkins uses to reach this server}"
UPDATE_CENTER_ID="${UPDATE_CENTER_ID:-ohmvir-nexus}"
DATA_DIR="${DATA_DIR:-/var/lib/update-center}"
OUTPUT_DIR="$DATA_DIR/www"
CACHE_DIR="$DATA_DIR/cache"
SIGNING_DIR="$DATA_DIR/signing"
APP_DIR="${UPDATE_CENTER_APP_DIR:-/opt/update-center2}"

# Cron may fire while a previous (slow) generation is still running.
exec 9>"${DATA_DIR}/.sync.lock"
if ! flock -n 9; then
  echo "[$(date)] Another update-center generation is still running; skipping."
  exit 0
fi

mkdir -p "$OUTPUT_DIR" "$CACHE_DIR"
echo "[$(date)] Scanning Nexus repository at: ${NEXUS_URL}..."

# update-center2 caches failed downloads as directories forever; drop them so a
# temporary Nexus outage does not hide a plugin release permanently.
find "$CACHE_DIR" -mindepth 2 -maxdepth 2 -type d -exec rm -rf {} +

# update-center2 uses Artifactory's AQL API. The local adapter translates Nexus
# asset-search responses, while forwarding artifact downloads to Nexus.
export ARTIFACTORY_URL="http://127.0.0.1:8765/"
export ARTIFACTORY_API_URL="http://127.0.0.1:8765/api/"
export ARTIFACTORY_REPOSITORY="releases"
export ARTIFACTORY_USERNAME="$NEXUS_USER"
export ARTIFACTORY_PASSWORD="$NEXUS_PASS"
export ARTIFACTORY_CACHEDIR="$CACHE_DIR"
# Plugin download links in update-center.json point at the files this server
# publishes under download/, instead of the default updates.jenkins.io.
export DOWNLOADS_ROOT_URL="${UPDATE_CENTER_URL%/}/download"
# Maintainers of the private plugins come from the adapter rather than
# reports.jenkins.io, otherwise every plugin is labelled "up for adoption".
export PLUGIN_MAINTAINERS_DATA_URL="http://127.0.0.1:8765/maintainers.index.json"
export MAINTAINERS_INFO_URL="http://127.0.0.1:8765/maintainers-info-report.json"
# GitHub enrichment is optional; empty values let update-center2 use its dumb mode.
export GITHUB_USERNAME="${GITHUB_USERNAME:-}"
export GITHUB_PASSWORD="${GITHUB_PASSWORD:-}"

# Generate into a staging directory and publish only complete, signed output.
STAGING_DIR="$(mktemp -d "${DATA_DIR}/www-staging.XXXXXX")"
trap 'rm -rf "$STAGING_DIR"' EXIT

cd "$APP_DIR"
java -Dfile.encoding=UTF-8 -cp "$APP_DIR/lib/*" io.jenkins.update_center.Main \
  --id "$UPDATE_CENTER_ID" \
  --www-dir "$STAGING_DIR" \
  --downloads-directory "$STAGING_DIR/download" \
  --key "$SIGNING_DIR/update-center.key" \
  --certificate "$SIGNING_DIR/update-center.crt" \
  --root-certificate "$SIGNING_DIR/update-center.crt"

cp "$SIGNING_DIR/update-center.crt" "$STAGING_DIR/update-center.crt"
if [ ! -s "$STAGING_DIR/update-center.json" ]; then
  echo "[$(date)] ERROR: update-center2 did not produce update-center.json"
  exit 1
fi

# Swap the new tree in; the download files are hard links into the cache.
chmod 755 "$STAGING_DIR"
rm -rf "$OUTPUT_DIR.old"
if [ -d "$OUTPUT_DIR" ]; then mv "$OUTPUT_DIR" "$OUTPUT_DIR.old"; fi
mv "$STAGING_DIR" "$OUTPUT_DIR"
rm -rf "$OUTPUT_DIR.old"
trap - EXIT

echo "[$(date)] Done! Published to ${OUTPUT_DIR}/update-center.json"
