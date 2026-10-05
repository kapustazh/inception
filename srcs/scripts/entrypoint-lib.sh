#!/bin/bash

info() {
    echo "[INFO] $*"
}

warn() {
    echo "[WARN] $*" >&2
}

error() {
    echo "[ERROR] $*" >&2
    exit 1
}

require_env() {
    local name="$1"

    [ -n "${!name-}" ] || error "Environment variable '$name' was not found"
}

require_nonempty_file() {
    local file="$1"

    [ -f "$file" ] || error "File '$file' not found"
    [ -s "$file" ] || error "File '$file' is empty"
}

read_secret() {
    local file="$1"

    require_nonempty_file "$file"
    tr -d '\r\n' < "$file"
}