#!/bin/bash
set -e

# Configuration
NEXUS_URL="${NEXUS_URL:?NEXUS_URL must be set}"
NEXUS_USER="${NEXUS_USER:?NEXUS_USER must be set}"
NEXUS_PASS="${NEXUS_PASS:?NEXUS_PASS must be set}"
OUTPUT_DIR="${OUTPUT_DIR:-/usr/share/nginx/html}"
mkdir -p "$OUTPUT_DIR"

EXECUTABLE="${UPDATE_CENTER_EXECUTABLE:-/opt/update-center2/bin/app}"
if [ ! -x "$EXECUTABLE" ]; then
  echo "[$(date)] ERROR: update-center2 executable is missing or not executable: ${EXECUTABLE}"
  exit 1
fi

echo "[$(date)] Scanning Nexus repository at: ${NEXUS_URL}..."

# update-center2 uses Artifactory's AQL API. The local adapter translates Nexus
# asset-search responses, while forwarding artifact downloads to Nexus.
export ARTIFACTORY_URL="http://127.0.0.1:8765/"
export ARTIFACTORY_API_URL="http://127.0.0.1:8765/api/"
export ARTIFACTORY_REPOSITORY="releases"
export ARTIFACTORY_USERNAME="$NEXUS_USER"
export ARTIFACTORY_PASSWORD="$NEXUS_PASS"
# GitHub enrichment is optional; empty values let update-center2 use its dumb mode.
export GITHUB_USERNAME="${GITHUB_USERNAME:-}"
export GITHUB_PASSWORD="${GITHUB_PASSWORD:-}"

cd /opt/update-center2
"$EXECUTABLE" --id "ohmvir-nexus" --www-dir "$OUTPUT_DIR"

echo "[$(date)] Done! Published to ${OUTPUT_DIR}/update-center.json"
