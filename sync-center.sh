#!/bin/bash
set -e

# Configuration
NEXUS_URL="${NEXUS_URL:-https://nexus.ohmvir.dev/repository/maven-releases}"
NEXUS_USER="${NEXUS_USER:-}"
NEXUS_PASS="${NEXUS_PASS:-}"
OUTPUT_DIR="${OUTPUT_DIR:-/usr/share/nginx/html}"
mkdir -p "$OUTPUT_DIR"

EXECUTABLE="${UPDATE_CENTER_EXECUTABLE:-$(find /opt/update-center2 /opt/update-center2/bin /opt/update-center2/appassembler/bin -type f \( -name "update-center2" -o -name "app" \) 2>/dev/null | head -n 1)}"
if [ -z "$EXECUTABLE" ]; then
  echo "[$(date)] ERROR: Could not locate the update-center2 executable under /opt/update-center2."
  exit 1
fi

chmod +x "$EXECUTABLE"

echo "[$(date)] Scanning Nexus repository at: ${NEXUS_URL}..."

# Construct optional Nexus credentials flags
set -- "$EXECUTABLE" --id "ohmvir-nexus" --www-dir "$OUTPUT_DIR" --nexus "$NEXUS_URL"
if [ -n "$NEXUS_USER" ] && [ -n "$NEXUS_PASS" ]; then
  set -- "$@" --nexus-username "$NEXUS_USER" --nexus-password "$NEXUS_PASS"
fi

# Execute the launcher script directly
"$@"

echo "[$(date)] Done! Published to ${OUTPUT_DIR}/update-center.json"