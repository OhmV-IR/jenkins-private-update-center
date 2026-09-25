#!/bin/sh
set -e

# Configuration
NEXUS_URL="${NEXUS_URL:-https://nexus.ohmvir.dev/repository/maven-releases}"
NEXUS_USER="${NEXUS_USER:-}"
NEXUS_PASS="${NEXUS_PASS:-}"
OUTPUT_DIR="/usr/share/nginx/html"
JAR_FILE="/tmp/update-center2.jar"

echo "[$(date)] Syncing plugins from Nexus: ${NEXUS_URL}..."

# Download Jenkins Update Center Generator JAR if missing
if [ ! -f "$JAR_FILE" ]; then
  echo "Downloading update-center2 generator tool..."
  curl -sSL "https://repo.jenkins-ci.org/public/io/jenkins/tools/update-center2/3.15/update-center2-3.15-bin.jar" -o "$JAR_FILE" || \
  curl -sSL "https://repo.jenkins-ci.org/public/io/jenkins/tools/update-center2/3.14/update-center2-3.14.jar" -o "$JAR_FILE"
fi

# Build authentication header if credentials are provided
AUTH_PARAM=""
if [ -n "$NEXUS_USER" ] && [ -n "$NEXUS_PASS" ]; then
  AUTH_PARAM="--nexus-username ${NEXUS_USER} --nexus-password ${NEXUS_PASS}"
fi

# Generate update-center.json into Nginx root
java -Dfile.encoding=UTF-8 -jar "$JAR_FILE" \
  --id "ohmvir-nexus" \
  --www-dir "$OUTPUT_DIR" \
  --nexus "$NEXUS_URL" \
  $AUTH_PARAM

echo "[$(date)] Generation complete! Served at /update-center.json"