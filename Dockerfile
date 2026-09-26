# --- Stage 1: Build update-center2 ---
FROM maven:3.9.6-eclipse-temurin-21 AS builder

RUN apt-get update && apt-get install -y git && rm -rf /var/lib/apt/lists/*
RUN git clone --depth 1 https://github.com/jenkins-infra/update-center2.git /app
WORKDIR /app

# Build appassembler package with all dependencies
RUN mvn clean package appassembler:assemble -DskipTests \
    -Dhttp.keepAlive=false \
    -Dmaven.wagon.http.retryHandler.count=3 \
    -Dmaven.wagon.rto=10000

# Locate generated appassembler output directory and stage it cleanly
RUN APP_DIR=$(find /app/target -type d \( -name "appassembler" -o -name "update-center2-*-bin" \) -print -quit) && \
    if [ -z "$APP_DIR" ]; then echo "No appassembler output found under /app/target" >&2; exit 1; fi && \
    cp -r "$APP_DIR" /app/target/dist

# --- Stage 2: Runtime image ---
FROM alpine:3.19

RUN apk add --no-cache \
    openjdk21-jre-headless \
    nginx \
    bash \
    python3

# Setup Nginx directory & lightweight site config
RUN mkdir -p /run/nginx /usr/share/nginx/html
RUN echo 'server { \
    listen 80; \
    root /usr/share/nginx/html; \
    location / { \
        autoindex on; \
        add_header Access-Control-Allow-Origin *; \
    } \
}' > /etc/nginx/http.d/default.conf

# Copy application bundle
COPY --from=builder /app/target/dist /opt/update-center2
COPY --from=builder /app/resources /opt/update-center2/resources

# Dynamically link the executable script to /usr/local/bin/update-center2
RUN BIN_PATH=$(find /opt/update-center2 -type f \( -name "update-center2" -o -name "app" \) -print -quit) && \
    if [ -z "$BIN_PATH" ]; then echo "No update-center2 executable found under /opt/update-center2" >&2; exit 1; fi && \
    chmod +x "$BIN_PATH" && \
    ln -sf "$BIN_PATH" /usr/local/bin/update-center2

# Copy sync script
COPY sync-center.sh /usr/local/bin/sync-center.sh
RUN chmod +x /usr/local/bin/sync-center.sh

# Copy the small adapter that exposes Nexus assets as the Artifactory API
COPY nexus-artifactory-proxy.py /usr/local/bin/nexus-artifactory-proxy.py

# Cron schedule
RUN echo "*/5 * * * * /usr/local/bin/sync-center.sh >> /var/log/cron.log 2>&1" > /etc/crontabs/root

# Start the Nexus adapter, perform an initial sync, then serve and schedule updates.
RUN printf '%s\n' \
    '#!/bin/sh' \
    'python3 -u /usr/local/bin/nexus-artifactory-proxy.py &' \
    'for attempt in $(seq 1 15); do wget -qO- http://127.0.0.1:8765/healthz >/dev/null 2>&1 && break; sleep 1; done' \
    '/usr/local/bin/sync-center.sh || echo "Initial update-center generation failed; nginx will still start."' \
    'crond -b -l 2' \
    'exec nginx -g "daemon off;"' > /entrypoint.sh && chmod +x /entrypoint.sh

EXPOSE 80
ENTRYPOINT ["/entrypoint.sh"]
