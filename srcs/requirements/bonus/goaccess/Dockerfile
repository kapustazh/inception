FROM debian:bookworm-slim

RUN apt-get update && \
    apt-get install -y --no-install-recommends goaccess && \
    rm -rf /var/lib/apt/lists/* && \
    mkdir -p /reports && chown www-data:www-data /reports

COPY requirements/bonus/goaccess/tools/docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
COPY scripts/entrypoint-lib.sh /usr/local/lib/entrypoint-lib.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh
USER www-data
EXPOSE 7890
ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
