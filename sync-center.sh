#!/bin/sh
set -e

NEXUS_URL="${NEXUS_URL:-https://nexus.ohmvir.dev/repository/maven-releases}"
NEXUS_USER="${NEXUS_USER:-}"
NEXUS_PASS="${NEXUS_PASS:-}"
OUTPUT_DIR="/usr/share/nginx/html"
JAR_FILE="/tmp/update-center2.jar"

echo "[$(date)] Syncing plugins from Nexus: ${NEXUS_URL}..."

# Download update-center2 tool cleanly with redirection (-L) and failure checks (-f)
if [ ! -f "$JAR_FILE" ] || [ ! -s "$JAR_FILE" ]; then
  echo "Downloading update-center2 generator tool..."
  # Clean up any bad state file
  rm -f "$JAR_FILE"
  
  # Fetch latest update-center2 jar directly from Jenkins Artifactory
  curl -fsSL "https://repo.jenkins-ci.org/releases/io/jenkins/tools/update-center2/3.15/update-center2-3.15-bin.jar" -o "$JAR_FILE" || \
  curl -fsSL "https://repo.jenkins-ci.org/public/io/jenkins/tools/update-center2/3.14/update-center2-3.14-bin.jar" -o "$JAR_FILE"
fi

# Build authentication header if credentials are set
AUTH_PARAM=""
if [ -n "$NEXUS_USER" ] && [ -n "$NEXUS_PASS" ]; then
  AUTH_PARAM="--nexus-username ${NEXUS_USER} --nexus-password ${NEXUS_PASS}"
fi

# Execute generator
java -Dfile.encoding=UTF-8 -jar "$JAR_FILE" \
  --id "ohmvir-nexus" \
  --www-dir "$OUTPUT_DIR" \
  --nexus "$NEXUS_URL" \
  $AUTH_PARAM

echo "[$(date)] Sync complete!"