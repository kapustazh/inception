FROM debian:bookworm-slim

ARG ADMINER_VERSION=6.1.2

RUN apt-get update && \
    apt-get install -y --no-install-recommends php8.2-cli php8.2-mysql curl ca-certificates && \
    rm -rf /var/lib/apt/lists/* && \
    mkdir -p /var/www/html && \
    curl -fsSL -o /var/www/html/index.php \
        https://github.com/vrana/adminer/releases/download/v${ADMINER_VERSION}/adminer-${ADMINER_VERSION}-mysql-en.php

USER www-data
WORKDIR /var/www/html
EXPOSE 8080
CMD ["php", "-S", "0.0.0.0:8080", "-t", "/var/www/html"]
