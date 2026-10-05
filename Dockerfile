# --- Stage 1: Build update-center2 ---
FROM maven:3.9.6-eclipse-temurin-21 AS builder

# Pin the generator: upstream warns about incompatible changes on master.
ARG UPDATE_CENTER2_REF=update-center2-3.18.4

RUN apt-get update && apt-get install -y git && rm -rf /var/lib/apt/lists/*
RUN git clone --depth 1 --branch "${UPDATE_CENTER2_REF}" https://github.com/jenkins-infra/update-center2.git /app
WORKDIR /app

# Local fixes for running update-center2 as a private update site.
COPY patches /patches
RUN git apply -v /patches/*.patch

# The package phase produces target/update-center2-<version>-bin, a flat
# directory with the generator jar and all of its runtime dependencies.
RUN mvn -B clean package -DskipTests \
    -Dhttp.keepAlive=false \
    -Dmaven.wagon.http.retryHandler.count=3 \
    -Dmaven.wagon.rto=10000

RUN set -- /app/target/update-center2-*-bin && \
    if [ "$#" -ne 1 ] || [ ! -d "$1" ]; then echo "Expected exactly one update-center2 -bin directory under /app/target" >&2; exit 1; fi && \
    cp -r "$1" /app/target/dist

# --- Stage 2: Runtime image ---
FROM alpine:3.19

RUN apk add --no-cache \
    openjdk21-jre-headless \
    nginx \
    bash \
    openssl \
    python3

# Persistent state lives under one volume so update-center2 can hard-link
# cached plugin files into the published download tree:
#   www/      published update site (served by nginx)
#   cache/    artifacts downloaded from Nexus
#   signing/  update site signing key and certificate
ENV DATA_DIR=/var/lib/update-center
RUN mkdir -p /run/nginx "$DATA_DIR/www" "$DATA_DIR/cache" "$DATA_DIR/signing"
RUN printf '%s\n' \
    'server {' \
    '    listen 80;' \
    '    root /var/lib/update-center/www;' \
    '    location / {' \
    '        autoindex on;' \
    '        add_header Access-Control-Allow-Origin *;' \
    '    }' \
    '}' > /etc/nginx/http.d/default.conf

# Copy application bundle
COPY --from=builder /app/target/dist /opt/update-center2/lib
COPY --from=builder /app/resources /opt/update-center2/resources

COPY sync-center.sh /usr/local/bin/sync-center.sh
COPY entrypoint.sh /entrypoint.sh
# The small adapter that exposes Nexus assets as the Artifactory API
COPY nexus-artifactory-proxy.py /usr/local/bin/nexus-artifactory-proxy.py
RUN chmod +x /usr/local/bin/sync-center.sh /entrypoint.sh

# Cron schedule; the container environment is saved by the entrypoint for cron jobs.
RUN echo "*/5 * * * * . /etc/update-center.env; /usr/local/bin/sync-center.sh >> /var/log/cron.log 2>&1" > /etc/crontabs/root

VOLUME /var/lib/update-center
EXPOSE 80
ENTRYPOINT ["/entrypoint.sh"]
