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

    # Read separately so a missing/invalid secret stops initialization.
    root_password=$(read_secret "$MARIADB_ROOT_PASSWORD_FILE")
    admin_password=$(read_secret "$MARIADB_ADMIN_PASSWORD_FILE")
    wp_password=$(read_secret "$MARIADB_WP_USER_PASSWORD_FILE")

    # The bootstrap session disables backslash escapes; double SQL string quotes.
    sql_string() {
        local value="$1"
        printf '%s' "${value//\'/\'\'}"
    }

    root_password=$(sql_string "$root_password")
    admin_password=$(sql_string "$admin_password")
    wp_password=$(sql_string "$wp_password")
    admin_user=$(sql_string "$MARIADB_ADMIN_USER")
    wp_user=$(sql_string "$MARIADB_WP_USER")
    database=${MARIADB_DATABASE//\`/\`\`}

    mysqld --user=mysql --bootstrap <<SQL
SET SESSION sql_mode = 'NO_BACKSLASH_ESCAPES';
FLUSH PRIVILEGES;
ALTER USER 'root'@'localhost' IDENTIFIED BY '${root_password}';
CREATE DATABASE IF NOT EXISTS \`${database}\`;
CREATE USER IF NOT EXISTS '${admin_user}'@'%' IDENTIFIED BY '${admin_password}';
GRANT ALL PRIVILEGES ON \`${database}\`.* TO '${admin_user}'@'%';
CREATE USER IF NOT EXISTS '${wp_user}'@'%' IDENTIFIED BY '${wp_password}';
GRANT ALL PRIVILEGES ON \`${database}\`.* TO '${wp_user}'@'%';
FLUSH PRIVILEGES;
SQL

    touch /var/lib/mysql/.inception_initialized

    info "MariaDB initialization finished"
fi

exec "$@"
