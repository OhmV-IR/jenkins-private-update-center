#!/bin/bash
set -e

# Configuration
NEXUS_URL="${NEXUS_URL:-}"
NEXUS_USER="${NEXUS_USER:-}"
NEXUS_PASS="${NEXUS_PASS:-}"
OUTPUT_DIR="/usr/share/nginx/html"
JAR_FILE="/usr/local/bin/update-center2.jar"

echo "[$(date)] Scanning Nexus repository at: ${NEXUS_URL}..."

# Construct optional Nexus credentials flags
AUTH_PARAM=""
if [ -n "$NEXUS_USER" ] && [ -n "$NEXUS_PASS" ]; then
  AUTH_PARAM="--nexus-username ${NEXUS_USER} --nexus-password ${NEXUS_PASS}"
fi

# Run generator against Nexus
java -Dfile.encoding=UTF-8 -jar "$JAR_FILE" \
  --id "ohmvir-nexus" \
  --www-dir "$OUTPUT_DIR" \
  --nexus "$NEXUS_URL" \
  $AUTH_PARAM

echo "[$(date)] Done! Published to /usr/share/nginx/html/update-center.json"