# --- Stage 1: Build update-center2 ---
FROM maven:3.9.6-eclipse-temurin-21 AS builder

RUN apt-get update && apt-get install -y git && rm -rf /var/lib/apt/lists/*
RUN git clone --depth 1 https://github.com/jenkins-infra/update-center2.git /app
WORKDIR /app

# Build appassembler output directory with all dependencies
RUN mvn clean package appassembler:assemble -DskipTests \
    -Dhttp.keepAlive=false \
    -Dmaven.wagon.http.retryHandler.count=3 \
    -Dmaven.wagon.rto=10000

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

# Copy the ENTIRE appassembler payload (binaries + lib/ folder)
COPY --from=builder /app/target/appassembler /opt/update-center2

# Copy runner script
COPY sync-center.sh /usr/local/bin/sync-center.sh
RUN chmod +x /usr/local/bin/sync-center.sh

# Add crontab entry (Runs every 5 minutes)
RUN echo "*/5 * * * * /usr/local/bin/sync-center.sh >> /var/log/cron.log 2>&1" > /etc/crontabs/root

# Bootstrapping entrypoint
RUN echo '#!/bin/sh' > /entrypoint.sh && \
    echo '/usr/local/bin/sync-center.sh' >> /entrypoint.sh && \
    echo 'crond -b -l 2' >> /entrypoint.sh && \
    echo 'exec nginx -g "daemon off;"' >> /entrypoint.sh && \
    chmod +x /entrypoint.sh

EXPOSE 80
ENTRYPOINT ["/entrypoint.sh"]