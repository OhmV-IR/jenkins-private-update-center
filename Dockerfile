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
RUN APP_DIR=$(find /app/target -type d -name "appassembler" -o -name "update-center2-*-bin" | head -n 1) && \
    cp -r "$APP_DIR" /app/target/dist

# --- Stage 2: Runtime image ---
FROM alpine:3.19

RUN apk add --no-cache \
    openjdk21-jre-headless \
    nginx \
    busybox-extras \
    bash

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

# Dynamically link the executable script to /usr/local/bin/update-center2
RUN BIN_PATH=$(find /opt/update-center2 -type f -name "update-center2" | head -n 1) && \
    chmod +x "$BIN_PATH" && \
    ln -s "$BIN_PATH" /usr/local/bin/update-center2

# Copy sync script
COPY sync-center.sh /usr/local/bin/sync-center.sh
RUN chmod +x /usr/local/bin/sync-center.sh

# Cron schedule
RUN echo "*/5 * * * * /usr/local/bin/sync-center.sh >> /var/log/cron.log 2>&1" > /etc/crontabs/root

# Bootstrapping entrypoint
RUN echo '#!/bin/sh' > /entrypoint.sh && \
    echo '/usr/local/bin/sync-center.sh' >> /entrypoint.sh && \
    echo 'crond -b -l 2' >> /entrypoint.sh && \
    echo 'exec nginx -g "daemon off;"' >> /entrypoint.sh && \
    chmod +x /entrypoint.sh

EXPOSE 80
ENTRYPOINT ["/entrypoint.sh"]