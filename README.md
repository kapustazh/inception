*This project has been created as part of the 42 curriculum by mnestere.*

# Inception

## Description

Inception is a 42 system administration project about building and operating a Docker infrastructure inside a virtual machine. It hosts a WordPress website behind HTTPS, with separate containers for the web server, PHP application and database. The project covers image builds, service networking, secrets and persistent storage.

The stack includes all five listed bonuses: Redis object caching, an FTP server, Adminer database administration, a static portfolio and a GoAccess traffic dashboard. Each of the eight services has its own Dockerfile based on `debian:bookworm-slim`.

| Service | Role | Access |
|---|---|---|
| NGINX | Terminates TLS and routes requests to the websites | HTTPS on port 443 |
| WordPress + PHP-FPM | Runs WordPress and its administration panel | [Website](https://mnestere.42.fr) · [Administration](https://mnestere.42.fr/wp-admin/) |
| MariaDB | Stores WordPress content, settings and accounts | Internal database connection |
| Redis | Required WordPress object cache | Internal connection on port 6379 |
| Adminer | Database administration using MariaDB credentials | [Database administration](https://adminer.mnestere.42.fr) |
| Static website | Serves the HTML, CSS and JavaScript portfolio | [Portfolio](https://me.mnestere.42.fr) |
| FTP | Manages files in the WordPress volume using explicit TLS | Port 21; passive data ports 21100–21104 |
| GoAccess | Reports requests, response codes and traffic from NGINX logs | [Traffic dashboard](https://stats.mnestere.42.fr) |

## Instructions

Run the project inside a Linux VM with Docker Engine, Docker Compose V2, GNU Make and OpenSSL installed. Your account must be able to run Docker commands. The initial build requires internet access.

Configure Docker's `data-root` as `/home/mnestere/data/docker` before the first start; see [VM storage setup](DEV_DOC.md#docker-storage) for the steps. This places ordinary named volumes under the host directory required by the subject.

From the repository root, create the local configuration:

```sh
cp srcs/.env.example srcs/.env
```

Review `srcs/.env` before starting. It contains the domain, database and WordPress account names, and paths to password and certificate files. Keep an existing `.env` when updating the project.

For access inside the VM, add this line to `/etc/hosts` with administrative privileges:

```text
127.0.0.1 mnestere.42.fr me.mnestere.42.fr stats.mnestere.42.fr adminer.mnestere.42.fr
```

For access from another machine, configure its hosts file with the VM's reachable IP address and ensure port 443 is reachable.

Build and start the stack:

```sh
make
make ps
```

`make` generates missing passwords and a self-signed TLS certificate, builds the images and starts the containers. Existing passwords and application data are preserved. Once WordPress finishes its first installation, open the URLs above and accept the self-signed certificate. WordPress login names are in `srcs/.env`; passwords are in the corresponding files under `secrets/`.

| Command | Effect |
|---|---|
| `make logs` | Follow the service logs |
| `make stop` / `make start` | Stop or resume existing containers |
| `make down` | Remove containers and the network; keep stored data |
| `make clean` | Also remove service images; keep stored data |
| `make fclean` / `make re` | Delete all stored application data; `re` then builds a fresh installation |

For FTP, use explicit TLS on port 21 with passive mode, the `FTP_USER` login from `.env`, and `secrets/ftp_password.txt`. Set `FTP_PASV_ADDRESS` to the address reachable from your client.

See [USER_DOC.md](USER_DOC.md) for daily operation and credentials, and [DEV_DOC.md](DEV_DOC.md) for configuration, rebuilds and troubleshooting.

## Architecture

```mermaid
flowchart TB
    browser["Browser"]
    ftp_client["FTP client"]

    subgraph vm["Virtual machine · Docker bridge: inception_backend"]
        nginx["NGINX<br/>HTTPS :443 · TLS 1.2 / 1.3"]
        wordpress["WordPress + PHP-FPM<br/>FastCGI :9000"]
        mariadb["MariaDB<br/>SQL :3306"]
        redis["Redis<br/>Required object cache :6379"]
        adminer["Adminer<br/>HTTP :8080"]
        portfolio["Static portfolio<br/>HTTP :8080"]
        goaccess["GoAccess<br/>WebSocket :7890"]
        ftp["vsftpd<br/>Explicit FTP over TLS"]
        files[("WordPress files<br/>wordpress_data")]

        nginx -->|"mnestere.42.fr · PHP requests"| wordpress
        wordpress -->|"Database queries"| mariadb
        wordpress -->|"Cache reads and writes"| redis
        wordpress -->|"Read and write"| files
        ftp -->|"Read and write"| files
        nginx -->|"Read-only files"| files
        nginx -->|"adminer.mnestere.42.fr"| adminer
        adminer -->|"Database administration"| mariadb
        nginx -->|"me.mnestere.42.fr"| portfolio
        nginx <-->|"stats.mnestere.42.fr/ws · live updates"| goaccess
    end

    browser -->|"HTTPS :443"| nginx
    ftp_client -->|"Explicit TLS :21 · passive data :21100-21104"| ftp
```

NGINX serves all websites on HTTPS port 443 and accepts TLS 1.2 and 1.3. It serves WordPress static files, sends PHP requests to PHP-FPM, and proxies portfolio requests to the static website container.

The FTP bonus additionally publishes port 21 and passive ports 21100–21104, as permitted for bonus services. It shares the WordPress file volume and requires encrypted login and data transfers.

GoAccess reads the NGINX access log and writes an HTML report. NGINX serves that report on the statistics hostname and proxies its WebSocket connection for live updates. Requests to the dashboard are excluded from the access log.

Four ordinary named volumes retain data under `/home/mnestere/data/docker/volumes/<volume-name>/_data`:

| Volume (Compose prefix: `inception_`) | Contents | Access |
|---|---|---|
| `mariadb_data` | Database files | MariaDB reads and writes database files |
| `wordpress_data` | WordPress files | WordPress and FTP read and write; NGINX reads |
| `nginx_logs` | Access logs | NGINX writes; GoAccess reads |
| `goaccess_reports` | Traffic report | GoAccess writes; NGINX reads |

These files survive container recreation and `make down`. GoAccess rebuilds its report from the retained logs when it starts. Portfolio files are included in its image. Redis keeps a disposable cache in memory, bounded to 128 MB; entries are rebuilt from MariaDB after a restart. Adminer has no persistent application data.

## Project description

Docker packages each service and its dependencies into a separate image. Compose defines how those containers share a network, storage and secrets; the Makefile prepares local files and runs Compose.

The repository contains:

- `srcs/requirements/`: service Dockerfiles, configuration files and startup scripts; bonus services are under `bonus/`.
- `srcs/scripts/entrypoint-lib.sh`: shared environment validation and secret-reading helpers.
- `srcs/docker-compose.yml`: service definitions, dependencies, network, volumes and secret mounts.
- `srcs/.env.example`: a template for the local configuration.
- `srcs/docker-daemon.json.example`: the VM's Docker storage setting.
- `Makefile`: build, startup, certificate generation and cleanup commands.

Startup scripts configure each service and use `exec` to run its daemon in the foreground. Compose provides process reaping through `init: true` and restarts containers with `restart: always`. WordPress starts after MariaDB and Redis pass health checks. Its entrypoint verifies Redis connectivity, installs the bundled Redis Object Cache plugin and enables its drop-in for both new and existing sites. Redis is required: an outage causes WordPress requests to fail until Redis returns. Database initialization and WordPress installation run only when their persisted state is absent.

### Virtual Machines vs Docker

A VM runs its own guest kernel; containers share the host kernel and isolate application processes, filesystems and networking. Here, the VM provides the Linux host, and Docker separates the services within it.

### Secrets vs Environment Variables

Environment variables configure domains, account names and file paths. Passwords are read from files mounted only into the services that use them. This keeps password values out of the Compose environment, where they would be visible through container inspection. Local Compose secrets use files on the VM; those source files and `.env` are ignored by Git.

### Docker Network vs Host Network

A bridge network gives containers separate network interfaces and lets them resolve each other by service name. Host networking shares the host's network stack. This project uses the `inception_backend` bridge and publishes NGINX port 443 plus the FTP control and passive ports; database, cache and application connections remain internal.

### Docker Volumes vs Bind Mounts

Named volumes are created and managed by Docker and persist independently of containers. Bind mounts map an existing host directory into a container. The application volumes here use Docker's default local driver without bind options. Docker's `data-root` setting places their files under `/home/mnestere/data/docker`, rather than choosing host paths in Compose.

## Resources

- [Dockerfile reference](https://docs.docker.com/reference/dockerfile/) — image build instructions.
- [Docker daemon configuration](https://docs.docker.com/engine/daemon/) — the `data-root` storage setting.
- [Compose file reference](https://docs.docker.com/reference/compose-file/) — services, networks, volumes and secrets.
- [NGINX documentation](https://nginx.org/en/docs/) — TLS, FastCGI and reverse proxy configuration.
- [WP-CLI handbook](https://make.wordpress.org/cli/handbook/) — WordPress installation and account management.
- [MariaDB documentation](https://mariadb.com/kb/en/) — database initialization, accounts and permissions.
- [Redis Object Cache configuration](https://github.com/rhubarbgroup/redis-cache) — WordPress cache configuration and failure behavior.
- [Adminer](https://www.adminer.org/) — database administration and releases.
- [vsftpd configuration manual](https://manpages.debian.org/bookworm/vsftpd/vsftpd.conf.5.en.html) — FTP accounts, TLS and passive connections.
- [GoAccess manual](https://goaccess.io/man) — log formats and live HTML reports.

AI assistance: Codex helped review and update service configuration, shared entrypoint helpers, MariaDB bootstrap SQL and WordPress password handling. It also assisted with bonus-service integration, integration checks, and the README, user and developer documentation.
