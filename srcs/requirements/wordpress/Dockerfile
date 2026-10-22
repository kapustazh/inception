FROM debian:bookworm-slim

ARG WP_VERSION=7.1.3
ARG WPCLI_VERSION=2.12.0
ARG REDIS_CACHE_VERSION=3.0.0

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        php8.2-fpm php8.2-mysql php8.2-gd php8.2-curl \
        php8.2-xml php8.2-mbstring php8.2-intl php8.2-zip \
        php8.2-cli php8.2-redis curl ca-certificates unzip && \
    rm -rf /var/lib/apt/lists/* && \
    curl -fsSL -o /usr/local/bin/wp \
        https://github.com/wp-cli/wp-cli/releases/download/v${WPCLI_VERSION}/wp-cli-${WPCLI_VERSION}.phar && \
    chmod +x /usr/local/bin/wp && \
    mkdir -p /usr/src/wordpress /var/www/html /run/php && \
    curl -fsSL https://wordpress.org/wordpress-${WP_VERSION}.tar.gz | \
        tar -xz --strip-components=1 -C /usr/src/wordpress && \
    curl -fsSL -o /tmp/redis-cache.zip \
        https://downloads.wordpress.org/plugin/redis-cache.${REDIS_CACHE_VERSION}.zip && \
    unzip -q /tmp/redis-cache.zip -d /usr/src/wordpress/wp-content/plugins && \
    rm /tmp/redis-cache.zip && \
    chown -R www-data:www-data /usr/src/wordpress /var/www/html /run/php

COPY requirements/wordpress/conf/www.conf /etc/php/8.2/fpm/pool.d/www.conf
COPY scripts/entrypoint-lib.sh /usr/local/lib/entrypoint-lib.sh
COPY requirements/wordpress/tools/docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh

RUN chmod +x /usr/local/bin/docker-entrypoint.sh

WORKDIR /var/www/html

EXPOSE 9000

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
CMD ["php-fpm8.2", "-F"]
