#!/bin/bash
set -e

# Configuration
NEXUS_URL="${NEXUS_URL:-https://nexus.ohmvir.dev/repository/maven-releases}"
NEXUS_USER="${NEXUS_USER:-}"
NEXUS_PASS="${NEXUS_PASS:-}"
OUTPUT_DIR="/usr/share/nginx/html"
EXECUTABLE="/opt/update-center2/bin/update-center2"

echo "[$(date)] Scanning Nexus repository at: ${NEXUS_URL}..."

# Construct optional Nexus credentials flags
AUTH_PARAM=""
if [ -n "$NEXUS_USER" ] && [ -n "$NEXUS_PASS" ]; then
  AUTH_PARAM="--nexus-username ${NEXUS_USER} --nexus-password ${NEXUS_PASS}"
fi

# Execute the launcher script directly
$EXECUTABLE \
  --id "ohmvir-nexus" \
  --www-dir "$OUTPUT_DIR" \
  --nexus "$NEXUS_URL" \
  $AUTH_PARAM

echo "[$(date)] Done! Published to ${OUTPUT_DIR}/update-center.json"