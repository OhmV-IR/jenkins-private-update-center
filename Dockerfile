# --- Stage 1: Build update-center2 with all dependencies ---
FROM maven:3.9.6-eclipse-temurin-21 AS builder

RUN apt-get update && apt-get install -y git && rm -rf /var/lib/apt/lists/*
RUN git clone --depth 1 https://github.com/jenkins-infra/update-center2.git /app
WORKDIR /app

# Build full package including assembly/shaded dependencies
RUN mvn clean package appassembler:assemble -DskipTests \
    -Dhttp.keepAlive=false \
    -Dmaven.wagon.http.retryHandler.count=3 \
    -Dmaven.wagon.rto=10000

# Locate and copy the executable jar with dependencies
RUN cp $(find target -name "update-center2-*-bin.jar" -o -name "update-center2-*-jar-with-dependencies.jar" | head -n 1) /app/target/update-center2.jar || \
    cp target/update-center2-*.jar /app/target/update-center2.jar

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

# Copy bundled JAR from Builder stage
COPY --from=builder /app/target/update-center2.jar /usr/local/bin/update-center2.jar

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