FROM alpine:3.19

# Install Java, Nginx, Curl, and Busybox Cron
RUN apk add --no-cache \
    openjdk17-jre-headless \
    nginx \
    curl \
    busybox-extras

# Configure Nginx
RUN mkdir -p /run/nginx /usr/share/nginx/html
RUN echo 'server { \
    listen 80; \
    root /usr/share/nginx/html; \
    location / { \
        autoindex on; \
        add_header Access-Control-Allow-Origin *; \
    } \
}' > /etc/nginx/http.d/default.conf

# Copy script
COPY sync-center.sh /usr/local/bin/sync-center.sh
RUN chmod +x /usr/local/bin/sync-center.sh

# Setup crontab (Run sync every 5 minutes)
RUN echo "*/5 * * * * /usr/local/bin/sync-center.sh >> /var/log/cron.log 2>&1" > /etc/crontabs/root

# Entrypoint script
RUN echo '#!/bin/sh' > /entrypoint.sh && \
    echo '/usr/local/bin/sync-center.sh' >> /entrypoint.sh && \
    echo 'crond -b -l 2' >> /entrypoint.sh && \
    echo 'exec nginx -g "daemon off;"' >> /entrypoint.sh && \
    chmod +x /entrypoint.sh

EXPOSE 80
ENTRYPOINT ["/entrypoint.sh"]