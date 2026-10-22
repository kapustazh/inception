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

All eight images are built from `debian:bookworm-slim` using project Dockerfiles. Containers share the `inception_backend` bridge network and resolve one another by Compose service name. NGINX publishes HTTPS port **443**. The FTP bonus additionally publishes control port **21** and passive data ports **21100–21104**.

| Service / image | Responsibility | Internal port | Browser endpoint |
|---|---|---|---|
| `nginx:0.1` | TLS termination, WordPress front end, bonus routing | 443 | `https://mnestere.42.fr` |
| `wordpress:0.1` | WordPress with PHP-FPM; no HTTP server | 9000 | `/` and `/wp-admin` through NGINX |
| `mariadb:0.1` | WordPress database | 3306 | Internal only |
| `goaccess:0.1` | Parse access logs and generate a live report | 7890, WebSocket | `https://stats.mnestere.42.fr` |
| `redis:0.1` | Required WordPress object cache | 6379 | Internal only |
| `adminer:0.1` | Database administration | 8080 | `https://adminer.mnestere.42.fr` |
| `ftp:0.1` | Manage WordPress files over explicit FTP/TLS | 21, 21100–21104 | FTP client |
| `static-website:0.1` | Serve the HTML/CSS/JS portfolio | 8080 | `https://me.mnestere.42.fr` |

NGINX sends PHP requests to `wordpress:9000`, proxies the portfolio to `static-website:8080`, serves GoAccess's generated HTML, and proxies `/ws` on the statistics host to `goaccess:7890`. It also proxies the Adminer hostname to `adminer:8080`. WordPress connects to `redis:6379`. Database, cache and application backend ports are not published. FTP clients connect directly to the FTP container through its published ports.

```text
inception/
├── Makefile
├── README.md, USER_DOC.md, DEV_DOC.md
├── secrets/                         # Local passwords and certificates; ignored by Git
└── srcs/
    ├── .env                         # Local configuration; ignored by Git
    ├── .env.example                 # Configuration template
    ├── docker-daemon.json.example   # VM storage configuration
    ├── .dockerignore
    ├── docker-compose.yml
    ├── scripts/entrypoint-lib.sh     # Single shared helper source
    └── requirements/
        ├── mariadb/                 # Dockerfile, server config and SQL bootstrap entrypoint
        ├── wordpress/               # Dockerfile, PHP-FPM config and entrypoint
        ├── nginx/                   # Dockerfile, configuration template and entrypoint
        └── bonus/
            ├── redis/               # Redis Dockerfile and memory-cache configuration
            ├── ftp/                 # vsftpd, TLS/passive configuration and entrypoint
            ├── adminer/             # PHP image with pinned Adminer download
            ├── goaccess/            # Dockerfile and analyzer entrypoint
            └── static-website/      # Dockerfile, NGINX config and public/
```

GoAccess implements the **service-of-your-choice** bonus; the portfolio implements the **static website** bonus. Redis implements object caching, and Adminer provides database administration. FTP shares the WordPress named volume and completes the fifth bonus item.

## 2. Environment setup

### Prerequisites

The VM needs Docker Engine, the Docker Compose V2 plugin, GNU Make, OpenSSL and a user that can run Docker commands. Git is needed to obtain the repository. Internet access is needed for the initial image builds. curl is used for HTTP checks.

Check the installed tools and Docker access:

```sh
docker version
docker compose version
make --version
openssl version
git --version
curl --version
```

If `docker version` cannot contact the daemon, check that Docker is running and that your account has access before building.

To connect to the existing VM from the workstation:

```sh
ssh -p 2222 mnestere@127.0.0.1
cd ~/inception
```

### Docker storage

Configure storage before the first project start. Compose uses ordinary named volumes with no bind options. Docker must store its data at `/home/mnestere/data/docker`, so the project volumes reside inside the subject's required `/home/mnestere/data` directory.

For a fresh Docker installation with no containers or volumes to preserve:

```sh
sudo systemctl stop docker.service docker.socket
sudo install -d /etc/docker
sudo install -m 644 srcs/docker-daemon.json.example /etc/docker/daemon.json
sudo systemctl enable --now docker.service
make check-storage
docker info --format '{{.DockerRootDir}}'
```

If `daemon.json` already contains other settings, merge the `data-root` key instead of replacing the file. Changing the data root on an existing engine does not migrate its files. Stop its workloads and Docker, back up and copy the previous root with ownership and permissions preserved, then update the configuration and restart Docker. Keep the old root until the migrated workloads have been verified. Existing bind-backed Inception volumes also need to be archived, recreated without driver options, and restored before starting the services; editing Compose alone does not convert existing volumes. See the [Docker daemon documentation](https://docs.docker.com/engine/daemon/).

The existing VM was migrated with its services stopped. Its previous Docker root and a separate archive of the four application directories are retained under `/var/lib/docker` and `/home/mnestere/inception-backups/` for rollback. These backups are outside normal project cleanup. To roll back, stop the current stack and Docker, restore the previous daemon configuration (the VM previously had no `daemon.json`), restore the four original directories from the backup into `/home/mnestere/data`, and restart Docker with `/var/lib/docker` as its data root. Start the stack using the saved `compose-old.yml` with `srcs/` as the Compose project directory. Do not delete the migrated root while investigating a rollback.

### Local configuration

On a fresh checkout, create the local environment file once:

```sh
cp srcs/.env.example srcs/.env
```

Edit it before the first build. Do not copy the example over an already configured `.env` during routine updates.

### Hostname resolution

For a browser **inside the VM**, edit `/etc/hosts` with administrative privileges and add:

```text
127.0.0.1 mnestere.42.fr me.mnestere.42.fr stats.mnestere.42.fr adminer.mnestere.42.fr
```

Check normal hostname resolution before testing the websites:

```sh
getent hosts mnestere.42.fr me.mnestere.42.fr stats.mnestere.42.fr adminer.mnestere.42.fr
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
| `FTP_USER`, `FTP_PASSWORD_FILE`, `FTP_PASSWORD_HOST_FILE` | Dedicated FTP account and its password secret |
| `FTP_PASV_ADDRESS` | Address advertised for passive transfers; use an address reachable from the FTP client |
| `WP_REDIS_HOST`, `WP_REDIS_PORT` | Required Redis connection; defaults in the example are `redis:6379` |
| `WP_TITLE`, `WP_ADMIN_USER`, `WP_ADMIN_EMAIL`, `WP_USER`, `WP_USER_EMAIL` | Initial WordPress site and user settings |
| `*_PASSWORD_HOST_FILE` | Password file paths on the VM, relative to `srcs/` |
| `*_PASSWORD_FILE` | Corresponding file paths inside the consuming container |
| `NGINX_SSL_CERTIFICATE_HOST_FILE`, `NGINX_SSL_CERTIFICATE_KEY_HOST_FILE` | Certificate and key sources on the VM |

Keep `DOMAIN_NAME` as a plain assignment, for example `DOMAIN_NAME=mnestere.42.fr`: the Makefile reads that line with `sed`. A value such as `../secrets/db_root_password.txt` resolves from `srcs/`, not from the repository root.

`LOGIN := mnestere` in the Makefile determines `/home/mnestere/data`. When adapting the project for another login, update `LOGIN`, `srcs/docker-daemon.json.example`, the daemon configuration, `.env`, usernames/emails and hostname mappings together. Changing the domain on an existing WordPress installation also requires updating its stored `home` and `siteurl` options; rebuilding alone does not rewrite them.

### Secrets

`make secrets` generates random passwords only for missing or empty files and sets their permissions to `600`. Existing non-empty passwords are preserved.

| Local file under `secrets/` | Container mount | Used by |
|---|---|---|
| `db_root_password.txt` | `/run/secrets/mariadb_root_pass` | MariaDB bootstrap and health check |
| `db_admin_password.txt` | `/run/secrets/mariadb_admin_pass` | MariaDB bootstrap; entered manually in Adminer |
| `db_wp_user_password.txt` | `/run/secrets/mariadb_wp_user_pass` | MariaDB and WordPress |
| `wp_admin_password.txt` | `/run/secrets/wp_admin_pass` | WordPress initialization |
| `wp_user_password.txt` | `/run/secrets/wp_user_pass` | WordPress initialization |
| `ftp_password.txt` | `/run/secrets/ftp_password` | FTP account setup on every start |

These are local file-backed Compose secrets, not a Swarm secret store. Each consuming container receives only the files declared in its service definition. `.env`, `secrets/` and generated certificates are Git-ignored.

Changing a password file does **not** change an existing MariaDB or WordPress account. Coordinate account changes with the corresponding secret and, for database credentials, WordPress's persisted `wp-config.php`. Do not use `make re` to rotate passwords on a site whose data you want to keep. FTP applies its password secret on every start; recreate only `ftp` after changing it.

### TLS certificates

`make cert` creates a self-signed certificate and private key in `secrets/certs/`. It regenerates the pair if the key is absent/empty, the certificate is expired/unreadable, or one of the four required hostnames is not covered. The key is set to mode `600`.

| Local file | NGINX mount | FTP mount |
|---|---|---|
| `certs/inception_nginx.crt` | `/etc/nginx/ssl/inception.crt` | `/etc/vsftpd/ssl/inception.crt` |
| `certs/inception_nginx.key` | `/etc/nginx/ssl/inception.key` | `/etc/vsftpd/ssl/inception.key` |

NGINX allows TLS 1.2 and 1.3. The certificate is self-signed, so the browser needs a local exception or trust configuration. To inspect its validity and names:

```sh
openssl x509 -in secrets/certs/inception_nginx.crt -noout -dates -ext subjectAltName
```

The Makefile generates certificates at these fixed paths. If you customize the certificate source paths in `.env`, keep the Makefile's generation paths consistent too. After replacing a certificate on a running stack, recreate NGINX and FTP so they load the new pair.

## 4. Build and startup

Start the complete stack:

```sh
make
```

The default target is `all`, which runs `up`. It checks `.env` and Docker's data root, creates missing secrets, prepares the certificate, checks hostname resolution, and runs Compose with `up -d --build`. Docker creates the named volumes.

Startup dependencies are:

1. MariaDB initializes if necessary and passes an authenticated `SELECT 1` health check.
2. Redis starts and passes a `PING` health check. WordPress starts only after both Redis and MariaDB are healthy; its own entrypoint also checks Redis connectivity.
3. WordPress becomes healthy when PHP-FPM is running and a WordPress CLI request loads the Redis-backed object cache. NGINX starts after WordPress is healthy; its own health check verifies that its master process exists.
4. GoAccess starts after NGINX is healthy and its access log has been created.
5. Adminer starts after MariaDB is healthy; the static website starts independently.
6. FTP starts after WordPress is healthy, so the shared website directory is initialized.

The WordPress health check gates NGINX startup on PHP-FPM and the Redis-backed WordPress runtime. NGINX's own health check only verifies that its process is running. NGINX resolves the Adminer, portfolio and GoAccess proxy backends at request time, so those stopped services do not prevent its configuration from loading. Redis is a required dependency of WordPress.

### Direct Compose commands

Compose does not require a host data-path variable. Run it from the repository root:

```sh
docker compose -f srcs/docker-compose.yml config --quiet
docker compose -f srcs/docker-compose.yml ps
```

The Compose file reads `srcs/.env` automatically. `make check-storage` verifies the daemon's data root; direct Compose commands do not run that guard.

## 5. Container management and inspection

### Makefile targets

| Command | Behavior | Effect on stored data |
|---|---|---|
| `make` / `make up` | Check configuration and storage, build images as needed and start/recreate services | Preserved; initial setup runs only where needed |
| `make ps` | Show project container status | None |
| `make logs` | Follow all service logs; Ctrl+C stops the log viewer | None |
| `make stop` | Stop existing containers | Preserved |
| `make start` | Start stopped containers; does not rebuild or apply changed configuration | Preserved |
| `make down` | Remove project containers and network | Volumes and host data preserved |
| `make clean` | Run `down --rmi all` to also remove project service images | Volumes and host data preserved |
| `make fclean` | Remove project containers, network, images and named volumes | **Deletes database, site files, logs and reports** |
| `make re` | Run `fclean`, then `up` | **Deletes stored data and creates a new installation** |
| `make check-env` | Check that `.env` exists and `DOMAIN_NAME` is set | None |
| `make check-storage` | Verify Docker uses `/home/mnestere/data/docker` | None |
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

Compose uses four ordinary named volumes with the default local driver and no bind options. With the configured Docker data root, each volume stores its files at `/home/mnestere/data/docker/volumes/<Docker name>/_data`. Use `docker volume inspect` to confirm the path; do not edit live volume files directly.

| Compose volume / Docker name | Container paths and access |
|---|---|
| `mariadb_data` / `inception_mariadb_data` | MariaDB `/var/lib/mysql`, read-write |
| `wordpress_data` / `inception_wordpress_data` | WordPress `/var/www/html`, read-write; NGINX same path, read-only |
| `nginx_logs` / `inception_nginx_logs` | NGINX `/var/log/inception`, read-write; GoAccess `/logs`, read-only |
| `goaccess_reports` / `inception_goaccess_reports` | GoAccess `/reports`, read-write; NGINX `/var/www/goaccess`, read-only |

Database rows, uploads, plugins, logs and generated reports survive container recreation and `make down`. The portfolio is included in its image and has no writable application state, so it needs no dedicated volume.

Initialization is conditional:

- MariaDB runs the SQL heredoc in `requirements/mariadb/tools/docker-entrypoint.sh` only when `/var/lib/mysql/.inception_initialized` is absent. The marker is written after successful bootstrap. Passwords and account names are SQL-escaped before substitution; the database identifier escapes backticks. There is no separate `init.sql` file or MariaDB `envsubst` step.
- WordPress creates `wp-config.php` only when absent, checks whether WordPress is installed, and creates the regular user only when missing. On every start it sets the Redis constants, copies the pinned plugin/drop-in from the image, and activates Redis Object Cache. Existing database and user passwords are preserved.
- GoAccess reprocesses the retained raw access log when it starts. Do not delete the log if you want to retain historical statistics.

Do not remove only a bootstrap marker or `wp-config.php` from an otherwise populated installation. Back up the database and WordPress files together before a destructive reset. A Docker volume is persistence, not an independent backup. `make fclean` removes only this Compose project's volumes; it never deletes Docker's data-root directory or unrelated volumes.

## 7. Development workflows

### Shared helpers and build contexts

MariaDB, WordPress, NGINX, GoAccess and FTP all copy `srcs/scripts/entrypoint-lib.sh` into `/usr/local/lib/entrypoint-lib.sh` and source it from their Bash entrypoints. The library uses Bash syntax, so these scripts must declare `#!/bin/bash`. Edit the shared source once; do not create copies in each service directory. Their build context is `srcs/`, and `srcs/.dockerignore` excludes local environment and secret/key files.

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

### Redis object cache

The image uses Debian's Redis server with a 128 MB limit and `allkeys-lru` eviction. It runs as the `redis` user, listens only on the internal Docker network and publishes no host port. Its cache is rebuilt from MariaDB, so disk persistence and an additional volume are unnecessary.

WordPress includes the PHP Redis extension and Redis Object Cache 3.0.0 in its image. Startup copies the plugin and drop-in into the existing WordPress volume, updates the `WP_REDIS_*` constants and activates the plugin. `WP_REDIS_GRACEFUL` and `WP_REDIS_DISABLED` are set to `false`: WordPress returns an error during a Redis outage. A direct container start also fails its Redis preflight before starting PHP-FPM. Compose health dependencies gate startup; they do not automatically stop an already running WordPress container when Redis stops.

```sh
docker exec redis redis-cli ping
docker exec -u www-data wordpress wp --path=/var/www/html redis status
docker exec redis redis-cli info stats
```

After visiting the website, Redis should contain keys and report cache hits. Redis restarts clear only cache entries. Never use `make re` to clear the cache: it deletes the database and WordPress files too.

### Adminer

The dedicated Debian image downloads Adminer 6.1.2's MySQL English PHP file and serves it with PHP on internal port 8080 as `www-data`. NGINX proxies `adminer.DOMAIN_NAME` through HTTPS. Adminer has no password baked into its image and receives no password secret: enter the database credentials in its login form.

Use server `mariadb`, the `MARIADB_ADMIN_USER` account, its `db_admin_password.txt` secret and `MARIADB_DATABASE`. MariaDB root is restricted to localhost and cannot log in through Adminer. Adminer does not depend on Redis, so database administration remains available during a cache outage.

### FTP server

The Debian-based `ftp` image runs vsftpd in the foreground and reuses the shared Bash entrypoint library. Only `FTP_USER` may log in; anonymous and unencrypted logins are disabled. The dedicated account has the same UID/GID as `www-data`, a non-login shell and a chroot at `/var/www/html`. This allows WordPress and FTP to edit the same files without recursively changing ownership or permissions. The writable chroot is intentional because it is the site's managed file root.

FTP uses explicit TLS on port 21 and encrypts passive data connections on ports 21100–21104. It mounts the existing certificate/key as secrets and shares `wordpress_data`, so it needs no additional data volume. Active-mode transfers are disabled. TLS session reuse is optional for compatibility with standard clients; encrypted control and data connections are still required.

Set `FTP_PASV_ADDRESS` to the address reachable by the client. The default loopback address is for access inside the VM. With NAT or forwarding, forward the control port and the five passive ports, preserving the passive port numbers. After changing FTP configuration or credentials:

```sh
docker compose -f srcs/docker-compose.yml up -d --build --force-recreate --no-deps ftp
```

For a listing from inside the VM, this command prompts for the FTP password:

```sh
curl --ssl-reqd --cacert secrets/certs/inception_nginx.crt --user ftp_user ftp://mnestere.42.fr/
```

Use the configured `FTP_USER` if it differs from the default. The health check reads the FTP greeting; login and transfer checks require an FTP client. FTP uploads appear immediately in the WordPress volume. Do not modify or remove existing site files just to test a connection.

### Portfolio

Edit `srcs/requirements/bonus/static-website/public/` and rebuild the service.

HTML, CSS and JavaScript are served directly. Cloudflare tooling and PHP are not required. Google Fonts are loaded externally; system font fallbacks are available offline.

## 8. Verification and troubleshooting

### Check actual browser URLs

First confirm hostname resolution, then request each endpoint normally:

```sh
getent hosts mnestere.42.fr me.mnestere.42.fr stats.mnestere.42.fr adminer.mnestere.42.fr
curl -kfsS -o /dev/null -w 'WordPress: %{http_code}\n' https://mnestere.42.fr
curl -kfsS -o /dev/null -w 'Portfolio: %{http_code}\n' https://me.mnestere.42.fr
curl -kfsS -o /dev/null -w 'Statistics: %{http_code}\n' https://stats.mnestere.42.fr
curl -kfsS -o /dev/null -w 'Adminer: %{http_code}\n' https://adminer.mnestere.42.fr
```

After startup, expect HTTP 200 for all four. `-k` is appropriate here for checking this local self-signed setup; it does not validate certificate trust. Open the pages in the browser too. Visit the main site and check that GoAccess's live report updates.

### Common failures

| Symptom | Checks and action |
|---|---|
| All hostname URLs fail, containers are up | Run `getent hosts`. Add/correct the entries on the machine running the browser. Check HTTPS forwarding if outside the VM. |
| `Set Docker data-root to ...` | Follow the Docker storage setup above; changing the daemon configuration requires a daemon restart and migration of existing data. |
| Browser rejects the certificate | Confirm the hostname is covered, then accept/trust the local self-signed certificate. A regenerated certificate may require a new browser exception. |
| WordPress returns 502 | Inspect `docker logs wordpress` and the MariaDB/Redis health checks. Confirm PHP-FPM is running; recreating WordPress can require reloading NGINX if its container IP changed. |
| WordPress reports a Redis connection error | Check Redis health and `docker logs redis`. Restart Redis; WordPress requires it even after startup. |
| FTP logs in but listing/transfers time out | Check `FTP_PASV_ADDRESS` and forwarding/firewall access to ports 21100–21104. Use passive mode. |
| FTP rejects the connection | Select explicit FTP over TLS on port 21 and use the FTP account/secret. Check `docker logs ftp`. |
| Adminer cannot log in | Use server `mariadb` and the database admin account/secret, not the WordPress administrator or MariaDB root account. |
| MariaDB is unhealthy | Check its logs and the root secret. Replacing the secret does not change the password of an existing database account. |
| Statistics page returns 404 during first startup | Check `docker logs goaccess` and whether `/reports/index.html` was generated. A missing report is not fixed by resetting the WordPress database. |
| Report opens but does not update | Check the browser's `/ws` WebSocket request. Expect status 101 through HTTPS port 443; inspect GoAccess and NGINX logs. |
| Portfolio returns 502 | Check the `static-website` container and logs. It listens on internal port 8080. |
| A changed file has no effect | Confirm it is inside the service's build context and rebuild/recreate that service. WordPress files already in its persistent volume are not replaced by changing the image. |
| Volume files show unfamiliar numeric owners | Container users have their own UIDs/GIDs. Inspect with `ls -ln`; do not apply `chmod 777` or change ownership blindly. |

Do not run `make fclean` or `make re` as a general troubleshooting step: both delete the data you may need to diagnose or recover.
