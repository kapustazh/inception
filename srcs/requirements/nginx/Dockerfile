FROM debian:bookworm-slim

RUN apt-get update && \
    apt-get install -y --no-install-recommends nginx gettext-base && \
    rm -rf /var/lib/apt/lists/*

COPY requirements/nginx/conf/nginx.conf.template /etc/nginx/nginx.conf.template
COPY requirements/nginx/tools/docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
COPY scripts/entrypoint-lib.sh /usr/local/lib/entrypoint-lib.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]

EXPOSE 443

CMD ["nginx", "-g", "daemon off;"]
