#!/bin/bash
set -Eeuo pipefail

source /usr/local/lib/entrypoint-lib.sh

require_env DOMAIN_NAME
require_env WP_TITLE
require_env WP_DB_HOST
require_env WP_DB_NAME
require_env WP_DB_USER
require_env WP_DB_PASSWORD_FILE
require_env WP_ADMIN_USER
require_env WP_ADMIN_EMAIL
require_env WP_ADMIN_PASSWORD_FILE
require_env WP_USER
require_env WP_USER_EMAIL
require_env WP_USER_PASSWORD_FILE
require_env WP_REDIS_HOST
require_env WP_REDIS_PORT

# Also enforce Redis when starting directly or after a Docker daemon restart.
php -r '$redis = new Redis(); $redis->connect(getenv("WP_REDIS_HOST"), (int) getenv("WP_REDIS_PORT"), 2); exit($redis->ping() ? 0 : 1);'

WP_DB_PASSWORD=$(read_secret "$WP_DB_PASSWORD_FILE")
WP_ADMIN_PASSWORD=$(read_secret "$WP_ADMIN_PASSWORD_FILE")
WP_USER_PASSWORD=$(read_secret "$WP_USER_PASSWORD_FILE")

# Pass arguments directly, without evaluating another shell command.
wp_cli() {
    runuser -u www-data -- wp --path=/var/www/html "$@"
}

# Compose waits for MariaDB and Redis health checks.
if [ ! -f /var/www/html/wp-config.php ]; then
    cp -a /usr/src/wordpress/. /var/www/html/
    wp_cli config create \
        --dbname="$WP_DB_NAME" \
        --dbuser="$WP_DB_USER" \
        --dbpass="$WP_DB_PASSWORD" \
        --dbhost="$WP_DB_HOST"
    # config create uses addslashes; config set serializes the exact PHP string.
    wp_cli config set DB_PASSWORD "$WP_DB_PASSWORD" --quiet
fi

# Apply cache configuration to both new and existing installations.
wp_cli config set WP_REDIS_HOST "$WP_REDIS_HOST" --quiet
wp_cli config set WP_REDIS_PORT "$WP_REDIS_PORT" --quiet
wp_cli config set WP_REDIS_CLIENT phpredis --quiet
wp_cli config set WP_REDIS_PREFIX "${DOMAIN_NAME}:" --quiet
wp_cli config set WP_REDIS_GRACEFUL false --raw --quiet
wp_cli config set WP_REDIS_DISABLED false --raw --quiet
mkdir -p /var/www/html/wp-content/plugins
cp -a /usr/src/wordpress/wp-content/plugins/redis-cache /var/www/html/wp-content/plugins/
cp -a /usr/src/wordpress/wp-content/plugins/redis-cache/includes/object-cache.php /var/www/html/wp-content/object-cache.php

if ! wp_cli core is-installed; then
    wp_cli core install \
        --url="https://$DOMAIN_NAME" \
        --title="$WP_TITLE" \
        --admin_user="$WP_ADMIN_USER" \
        --admin_password="$WP_ADMIN_PASSWORD" \
        --admin_email="$WP_ADMIN_EMAIL" \
        --skip-email
fi

if ! wp_cli user get "$WP_USER" >/dev/null 2>&1; then
    wp_cli user create "$WP_USER" "$WP_USER_EMAIL" \
        --role=author --user_pass="$WP_USER_PASSWORD"
    # WP-CLI 2.12 escapes user_pass before insertion; set the exact secret via WordPress.
    runuser -u www-data -- env "INCEPTION_USER_PASSWORD=$WP_USER_PASSWORD" \
        "INCEPTION_USER=$WP_USER" wp --path=/var/www/html eval \
        'wp_set_password(getenv("INCEPTION_USER_PASSWORD"), get_user_by("login", getenv("INCEPTION_USER"))->ID);'
fi

wp_cli plugin activate redis-cache
wp_cli eval 'if (!wp_using_ext_object_cache()) { exit(1); }'

exec "$@"
