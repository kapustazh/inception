#!/bin/bash
set -eu

source /usr/local/lib/entrypoint-lib.sh

require_env DOMAIN_NAME

exec goaccess /logs/access.log \
    --no-global-config \
    --log-format=COMBINED \
    --date-format=%d/%b/%Y \
    --time-format=%T \
    --output=/reports/index.html \
    --real-time-html \
    --addr=0.0.0.0 \
    --port=7890 \
    --ws-url="wss://stats.${DOMAIN_NAME}:443/ws" \
    --origin="https://stats.${DOMAIN_NAME}" \
    --no-parsing-spinner \
    --html-report-title="Inception traffic"
