# Developer Documentation

This guide explains how to configure, build, inspect and maintain the Inception stack inside the VM. Run project commands from `~/inception` unless stated otherwise. For browser access and everyday use, see [USER_DOC.md](USER_DOC.md).

## Contents

1. [Architecture and source layout](#1-architecture-and-source-layout)
2. [Environment setup](#2-environment-setup)
3. [Configuration, secrets and certificates](#3-configuration-secrets-and-certificates)
4. [Build and startup](#4-build-and-startup)
5. [Container management and inspection](#5-container-management-and-inspection)
6. [Storage and persistence](#6-storage-and-persistence)
7. [Development workflows](#7-development-workflows)
8. [Verification and troubleshooting](#8-verification-and-troubleshooting)

## 1. Architecture and source layout

All five images are built from `debian:bookworm-slim` using project Dockerfiles. Containers share the `inception_backend` bridge network and resolve one another by Compose service name. Only the front NGINX publishes a host port: **443**.

| Service / image | Responsibility | Internal port | Browser endpoint |
|---|---|---|---|
| `nginx:0.1` | TLS termination, WordPress front end, bonus routing | 443 | `https://mnestere.42.fr` |
| `wordpress:0.1` | WordPress with PHP-FPM; no HTTP server | 9000 | `/` and `/wp-admin` through NGINX |
| `mariadb:0.1` | WordPress database | 3306 | Internal only |
| `goaccess:0.1` | Parse access logs and generate a live report | 7890, WebSocket | `https://stats.mnestere.42.fr` |
| `static-website:0.1` | Serve the HTML/CSS/JS portfolio | 8080 | `https://me.mnestere.42.fr` |

NGINX sends PHP requests to `wordpress:9000`, proxies the portfolio to `static-website:8080`, serves GoAccess's generated HTML, and proxies `/ws` on the statistics host to `goaccess:7890`. The extra internal ports are not published to the VM.

```text
inception/
├── Makefile
├── README.md, USER_DOC.md, DEV_DOC.md
├── secrets/                         # Local passwords and certificates; ignored by Git
├── srcs/
│   ├── .env                         # Local configuration; ignored by Git
│   ├── .env.example                 # Configuration template
│   ├── .dockerignore
│   ├── docker-compose.yml
│   ├── scripts/entrypoint-lib.sh    # Single shared helper source
│   └── requirements/
│       ├── mariadb/                 # Dockerfile, server config and SQL bootstrap entrypoint
│       ├── wordpress/               # Dockerfile, PHP-FPM config and entrypoint
│       ├── nginx/                   # Dockerfile, configuration template and entrypoint
│       └── bonus/
│           ├── goaccess/            # Dockerfile and analyzer entrypoint
│           └── static-website/      # Dockerfile, NGINX config and public/
└── tests/smoke.py                    # Isolated integration check
```

GoAccess implements the **service-of-your-choice** bonus; the portfolio implements the **static website** bonus. Redis, FTP and Adminer are not implemented.

## 2. Environment setup

### Prerequisites

The VM needs Docker Engine, the Docker Compose V2 plugin, GNU Make, OpenSSL and a user that can run Docker commands. Git is needed to obtain the repository. Internet access is needed for the initial image builds. Python 3 and curl are required for the smoke test.

Check the installed tools and Docker access:

```sh
docker version
docker compose version
make --version
openssl version
git --version
python3 --version
curl --version
```

If `docker version` cannot contact the daemon, check that Docker is running and that your account has access before building.

To connect to the existing VM from the workstation:

```sh
ssh -p 2222 mnestere@127.0.0.1
cd ~/inception
```

### Local configuration

On a fresh checkout, create the local environment file once:

```sh
cp srcs/.env.example srcs/.env
```

Edit it before the first build. Do not copy the example over an already configured `.env` during routine updates.

### Hostname resolution

For a browser **inside the VM**, edit `/etc/hosts` with administrative privileges and add:

```text
127.0.0.1 mnestere.42.fr me.mnestere.42.fr stats.mnestere.42.fr
```

Check normal hostname resolution before testing the websites:

```sh
getent hosts mnestere.42.fr me.mnestere.42.fr stats.mnestere.42.fr
```

For a browser on the workstation, configure that workstation's hosts file instead. Point the names at the VM's reachable address, or at the local address used by an HTTPS forwarding rule. Forwarding SSH port 2222 alone does not forward website traffic on port 443.

`make` warns if a hostname does not resolve; it does not edit `/etc/hosts`. A successful `curl --resolve` test bypasses DNS and therefore does not prove that the normal browser URL will resolve.

## 3. Configuration, secrets and certificates

### Environment variables

`srcs/.env` contains non-sensitive settings and paths to local secret files.

| Variables | Purpose |
|---|---|
| `DOMAIN_NAME` | Main hostname; NGINX derives `me.DOMAIN_NAME` and `stats.DOMAIN_NAME` from it |
| `MARIADB_DATABASE`, `MARIADB_ADMIN_USER`, `MARIADB_WP_USER` | Database and account names created during initialization |
| `WP_DB_HOST`, `WP_DB_NAME`, `WP_DB_USER` | WordPress's connection to MariaDB |
| `WP_TITLE`, `WP_ADMIN_USER`, `WP_ADMIN_EMAIL`, `WP_USER`, `WP_USER_EMAIL` | Initial WordPress site and user settings |
| `*_PASSWORD_HOST_FILE` | Password file paths on the VM, relative to `srcs/` |
| `*_PASSWORD_FILE` | Corresponding file paths inside the consuming container |
| `NGINX_SSL_CERTIFICATE_HOST_FILE`, `NGINX_SSL_CERTIFICATE_KEY_HOST_FILE` | Certificate and key sources on the VM |

Keep `DOMAIN_NAME` as a plain assignment, for example `DOMAIN_NAME=mnestere.42.fr`: the Makefile reads that line with `sed`. A value such as `../secrets/db_root_password.txt` resolves from `srcs/`, not from the repository root.

`LOGIN := mnestere` in the Makefile determines `/home/mnestere/data`. When adapting the project for another login, update `LOGIN`, `.env`, usernames/emails and hostname mappings together. Changing the domain on an existing WordPress installation also requires updating its stored `home` and `siteurl` options; rebuilding alone does not rewrite them.

### Secrets

`make secrets` generates random passwords only for missing or empty files and sets their permissions to `600`. Existing non-empty passwords are preserved.

| Local file under `secrets/` | Container mount | Used by |
|---|---|---|
| `db_root_password.txt` | `/run/secrets/mariadb_root_pass` | MariaDB bootstrap and health check |
| `db_admin_password.txt` | `/run/secrets/mariadb_admin_pass` | MariaDB bootstrap |
| `db_wp_user_password.txt` | `/run/secrets/mariadb_wp_user_pass` | MariaDB and WordPress |
| `wp_admin_password.txt` | `/run/secrets/wp_admin_pass` | WordPress initialization |
| `wp_user_password.txt` | `/run/secrets/wp_user_pass` | WordPress initialization |

These are local file-backed Compose secrets, not a Swarm secret store. Each consuming container receives only the files declared in its service definition. `.env`, `secrets/` and generated certificates are Git-ignored.

Changing a password file does **not** change an existing MariaDB or WordPress account. Coordinate account changes with the corresponding secret and, for database credentials, WordPress's persisted `wp-config.php`. Do not use `make re` to rotate passwords on a site whose data you want to keep.

### TLS certificates

`make cert` creates a self-signed certificate and private key in `secrets/certs/`. It regenerates the pair if the key is absent/empty, the certificate is expired/unreadable, or one of the three required hostnames is not covered. The key is set to mode `600`.

| Local file | NGINX mount |
|---|---|
| `certs/inception_nginx.crt` | `/etc/nginx/ssl/inception.crt` |
| `certs/inception_nginx.key` | `/etc/nginx/ssl/inception.key` |

NGINX allows TLS 1.2 and 1.3. The certificate is self-signed, so the browser needs a local exception or trust configuration. To inspect its validity and names:

```sh
openssl x509 -in secrets/certs/inception_nginx.crt -noout -dates -ext subjectAltName
```

The Makefile generates certificates at these fixed paths. If you customize the certificate source paths in `.env`, keep the Makefile's generation paths consistent too. After replacing a certificate on a running stack, recreate NGINX so it loads the new pair.

## 4. Build and startup

Start the complete stack:

```sh
make
```

The default target is `all`, which runs `up`. It checks `.env`, creates missing secrets, prepares the certificate, creates the four host data directories, checks hostname resolution, and runs Compose with `up -d --build`.

Startup dependencies are:

1. MariaDB initializes if necessary and passes an authenticated `SELECT 1` health check.
2. WordPress starts after MariaDB is healthy.
3. NGINX starts after the WordPress container has started; its health check verifies that its master process exists.
4. GoAccess starts after NGINX is healthy and its access log has been created.
5. The static website starts independently.

The NGINX health check does not verify WordPress's HTTP response. During initial WordPress installation, HTTPS may briefly return 502 before PHP-FPM is ready. NGINX resolves bonus proxy backends at request time, so a stopped bonus does not block the main site's NGINX startup.

### Direct Compose commands

The Makefile exports `DATA_DIR`. In a separate shell, set it before invoking Compose directly:

```sh
export DATA_DIR=/home/mnestere/data
docker compose -f srcs/docker-compose.yml config --quiet
docker compose -f srcs/docker-compose.yml ps
```

The Compose file reads `srcs/.env` automatically. Without `DATA_DIR`, it deliberately fails with `run through make` rather than choosing an unintended volume path. The direct Compose examples below assume this export remains set in your shell.

## 5. Container management and inspection

### Makefile targets

| Command | Behavior | Effect on stored data |
|---|---|---|
| `make` / `make up` | Prepare configuration, build images as needed and start/recreate services | Preserved; initial setup runs only where needed |
| `make ps` | Show project container status | None |
| `make logs` | Follow all service logs; Ctrl+C stops the log viewer | None |
| `make stop` | Stop existing containers | Preserved |
| `make start` | Start stopped containers; does not rebuild or apply changed configuration | Preserved |
| `make down` | Remove project containers and network | Volumes and host data preserved |
| `make clean` | Run `down --rmi all` to also remove project service images | Volumes and host data preserved |
| `make fclean` | Remove containers, network, images and volumes, then delete the contents of `/home/mnestere/data` | **Deletes database, site files, logs and reports** |
| `make re` | Run `fclean`, then `up` | **Deletes stored data and creates a new installation** |
| `make check-env` | Check that `.env` exists and `DOMAIN_NAME` is set | None |
| `make secrets` | Fill missing/empty password files | Existing non-empty files preserved |
| `make cert` | Check or regenerate the TLS pair | May replace certificate/key; application data preserved |

Use `make` for routine code changes. `make re` is a destructive reset. Cleanup does not delete the local `.env` or files under `secrets/`.

### Inspect individual services

```sh
docker compose -f srcs/docker-compose.yml logs --tail 50 nginx goaccess
docker compose -f srcs/docker-compose.yml logs --tail 50 mariadb wordpress
docker exec nginx nginx -t
docker exec -u www-data wordpress wp --path=/var/www/html core version
docker exec -u www-data wordpress wp --path=/var/www/html user list
```

Open an interactive database shell; enter the root password from your local secret when prompted:

```sh
docker exec -it mariadb mariadb -u root -p
```

For a Docker resource overview:

```sh
docker ps -a
docker image ls
docker volume ls
docker volume inspect inception_mariadb_data inception_wordpress_data
docker network inspect inception_backend
docker system df
```

`docker ps -a` lists all containers on the VM, including unrelated ones; `make ps` is scoped to this project. An `EXPOSE` port shown as `9000/tcp` is internal. A mapping such as `0.0.0.0:443->443/tcp` is published on the VM.

## 6. Storage and persistence

Compose uses four named volumes with the local driver's `type: none`, `o: bind` and explicit host directories. Services reference the volume names; the data is stored under `/home/mnestere/data`.

| Compose volume / Docker name | Host directory | Container paths and access |
|---|---|---|
| `mariadb_data` / `inception_mariadb_data` | `mariadb/` | MariaDB `/var/lib/mysql`, read-write |
| `wordpress_data` / `inception_wordpress_data` | `wordpress/` | WordPress `/var/www/html`, read-write; NGINX same path, read-only |
| `nginx_logs` / `inception_nginx_logs` | `nginx-logs/` | NGINX `/var/log/inception`, read-write; GoAccess `/logs`, read-only |
| `goaccess_reports` / `inception_goaccess_reports` | `goaccess/` | GoAccess `/reports`, read-write; NGINX `/var/www/goaccess`, read-only |

Database rows, uploads, plugins, logs and generated reports survive container recreation and `make down`. The portfolio is included in its image and has no writable application state, so it needs no dedicated volume.

Initialization is conditional:

- MariaDB runs the SQL heredoc in `requirements/mariadb/tools/docker-entrypoint.sh` only when `/var/lib/mysql/.inception_initialized` is absent. The marker is written after successful bootstrap. Passwords and account names are SQL-escaped before substitution; the database identifier escapes backticks. There is no separate `init.sql` file or MariaDB `envsubst` step.
- WordPress creates `wp-config.php` only when absent, checks whether WordPress is installed, and creates the regular user only when missing.
- GoAccess reprocesses the retained raw access log when it starts. Do not delete the log if you want to retain historical statistics.

Do not remove only a bootstrap marker or `wp-config.php` from an otherwise populated installation. Back up the database and WordPress files together before a destructive reset. A Docker volume is persistence, not an independent backup.

## 7. Development workflows

### Shared helpers and build contexts

MariaDB, WordPress, NGINX and GoAccess all copy `srcs/scripts/entrypoint-lib.sh` into `/usr/local/lib/entrypoint-lib.sh` and source it from their Bash entrypoints. The library uses Bash syntax, so these scripts must declare `#!/bin/bash`. Edit the shared source once; do not create copies in each service directory. Their build context is `srcs/`, and `srcs/.dockerignore` excludes local environment and secret/key files.

The static website uses its own service directory as its build context. Each service has its own Dockerfile. Daemons run in the foreground; entrypoint scripts use `exec`, and Compose's `init: true` provides process reaping. All services use `restart: always`.

### Change one service without resetting data

For example, after editing the portfolio files or GoAccess entrypoint:

```sh
docker compose -f srcs/docker-compose.yml up -d --build --no-deps static-website
docker compose -f srcs/docker-compose.yml up -d --build --no-deps goaccess
```

After editing the front NGINX configuration:

```sh
docker compose -f srcs/docker-compose.yml up -d --build --no-deps nginx
docker exec nginx nginx -t
```

`--no-deps` assumes the required dependencies are already running. Use `make` for a complete start. Changes to image contents, environment or Compose mounts require rebuilding/recreating the affected container; restarting an old container does not apply them.

### GoAccess

The main website and portfolio write access logs in explicit COMBINED format. The GoAccess entrypoint specifies the matching log/date/time formats and uses built-in live HTML mode. No shell polling loop, scheduler or Node.js runtime is involved.

The report is served at the statistics hostname. Its WebSocket uses public HTTPS port 443 through NGINX, while GoAccess listens internally on 7890. Keep the explicit `:443/ws` in the generated WebSocket URL: GoAccess otherwise appends its internal port to the supplied URL. The statistics host excludes its own access traffic from the report.

This VM setup uses one unrotated access log. For sustained traffic, introduce log rotation and verify how the analyzer follows the rotated/reopened file before relying on retained statistics.

### Portfolio

Edit `srcs/requirements/bonus/static-website/public/` and rebuild the service.

HTML, CSS and JavaScript are served directly. Cloudflare tooling and PHP are not required. Google Fonts are loaded externally; system font fallbacks are available offline.

## 8. Verification and troubleshooting

### Check actual browser URLs

First confirm hostname resolution, then request each endpoint normally:

```sh
getent hosts mnestere.42.fr me.mnestere.42.fr stats.mnestere.42.fr
curl -kfsS -o /dev/null -w 'WordPress: %{http_code}\n' https://mnestere.42.fr
curl -kfsS -o /dev/null -w 'Portfolio: %{http_code}\n' https://me.mnestere.42.fr
curl -kfsS -o /dev/null -w 'Statistics: %{http_code}\n' https://stats.mnestere.42.fr
```

After startup, expect HTTP 200 for all three. `-k` is appropriate here for checking this local self-signed setup; it does not validate certificate trust. Open the pages in the browser too. Visit the main site and check that GoAccess's live report updates.

### Isolated integration test

After building the images:

```sh
python3 tests/smoke.py
```

The test requires Python 3, curl, Docker access, the local `.env`/certificate files and unused VM port `127.0.0.1:8443`. It uses a separate Compose project, network, temporary named volumes and dummy credentials. It does not use the live database or WordPress volume.

It verifies fresh initialization; special characters in the WordPress title and MariaDB/WordPress passwords; HTTPS; the GoAccess report, generated WebSocket URL and upgrade response; portfolio HTML/CSS/JS; and WordPress data persistence after container recreation. Test resources are removed in its cleanup handler. It does not replace the normal DNS/browser checks above.

### Common failures

| Symptom | Checks and action |
|---|---|
| All hostname URLs fail, containers are up | Run `getent hosts`. Add/correct the entries on the machine running the browser. Check HTTPS forwarding if outside the VM. |
| `required variable DATA_DIR` / `run through make` | Use a Makefile target or export `DATA_DIR=/home/mnestere/data` before direct Compose commands. |
| Browser rejects the certificate | Confirm the hostname is covered, then accept/trust the local self-signed certificate. A regenerated certificate may require a new browser exception. |
| WordPress returns 502 | Inspect `docker logs wordpress` and MariaDB health. NGINX may start before WordPress's initial installation finishes. |
| MariaDB is unhealthy | Check its logs and the root secret. Replacing the secret does not change the password of an existing database account. |
| Statistics page returns 404 during first startup | Check `docker logs goaccess` and whether `/reports/index.html` was generated. A missing report is not fixed by resetting the WordPress database. |
| Report opens but does not update | Check the browser's `/ws` WebSocket request. Expect status 101 through HTTPS port 443; inspect GoAccess and NGINX logs. |
| Portfolio returns 502 | Check the `static-website` container and logs. It listens on internal port 8080. |
| A changed file has no effect | Confirm it is inside the service's build context and rebuild/recreate that service. WordPress files already in its persistent volume are not replaced by changing the image. |
| Host data directories show unfamiliar numeric owners | Container users have their own UIDs/GIDs. Inspect with `ls -ln`; do not apply `chmod 777` or change ownership blindly. |

Do not run `make fclean` or `make re` as a general troubleshooting step: both delete the data you may need to diagnose or recover.
