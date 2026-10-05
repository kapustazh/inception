#!/bin/bash

set -Eeuo pipefail

source /usr/local/lib/entrypoint-lib.sh

require_env MARIADB_DATABASE
require_env MARIADB_ADMIN_USER
require_env MARIADB_WP_USER

require_env MARIADB_ROOT_PASSWORD_FILE
require_env MARIADB_ADMIN_PASSWORD_FILE
require_env MARIADB_WP_USER_PASSWORD_FILE

mkdir -p /run/mysqld
chown -R mysql:mysql /run/mysqld /var/lib/mysql

if [ ! -f /var/lib/mysql/.inception_initialized ]; then
    info "Initializing MariaDB..."

    mariadb-install-db \
        --user=mysql \
        --datadir=/var/lib/mysql \
        > /dev/null

    MYSQL_ROOT_PASSWORD=$(read_secret "$MARIADB_ROOT_PASSWORD_FILE") \
    MYSQL_ADMIN_PASSWORD=$(read_secret "$MARIADB_ADMIN_PASSWORD_FILE") \
    MARIADB_WP_USER_PASSWORD=$(read_secret "$MARIADB_WP_USER_PASSWORD_FILE") \
    envsubst \
        '$MYSQL_ROOT_PASSWORD $MYSQL_ADMIN_PASSWORD $MARIADB_WP_USER_PASSWORD
         $MARIADB_ADMIN_USER $MARIADB_DATABASE $MARIADB_WP_USER' \
        < /etc/mysql/init.sql \
        | mysqld --user=mysql --bootstrap

    touch /var/lib/mysql/.inception_initialized

    info "MariaDB initialization finished"
fi

exec "$@"