#!/bin/bash
set -Eeuo pipefail

source /usr/local/lib/entrypoint-lib.sh

require_env FTP_USER
require_env FTP_PASSWORD_FILE
require_env FTP_PASV_ADDRESS
[[ "$FTP_USER" =~ ^[a-z_][a-z0-9_-]*$ && ${#FTP_USER} -le 32 ]] || error "Invalid FTP_USER"
[[ "$FTP_PASV_ADDRESS" =~ ^[A-Za-z0-9.-]+$ ]] || error "Invalid FTP_PASV_ADDRESS"

FTP_PASSWORD=$(read_secret "$FTP_PASSWORD_FILE")
[ -n "$FTP_PASSWORD" ] || error "FTP password must not be empty"

# Use WordPress's owner ID so uploads stay writable without changing volume ownership.
if ! id "$FTP_USER" >/dev/null 2>&1; then
    useradd --non-unique --uid "$(id -u www-data)" --gid "$(id -g www-data)" \
        --home-dir /var/www/html --no-create-home --shell /usr/sbin/nologin "$FTP_USER"
fi
[ "$(id -u "$FTP_USER")" = "$(id -u www-data)" ] || error "FTP_USER must use WordPress's owner ID"
printf '%s:%s\n' "$FTP_USER" "$FTP_PASSWORD" | chpasswd
unset FTP_PASSWORD
printf '%s\n' "$FTP_USER" > /etc/vsftpd.user_list
envsubst '${FTP_PASV_ADDRESS}' < /etc/vsftpd.conf.template > /etc/vsftpd.conf

exec "$@"
