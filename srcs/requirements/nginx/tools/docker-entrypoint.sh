#!/bin/bash
set -eu

source /usr/local/lib/entrypoint-lib.sh

require_env DOMAIN_NAME

envsubst '${DOMAIN_NAME}' < /etc/nginx/nginx.conf.template > /etc/nginx/nginx.conf
mkdir -p /var/log/inception
touch /var/log/inception/access.log
chmod 644 /var/log/inception/access.log
nginx -t
exec "$@"
