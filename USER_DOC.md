# User documentation

## Services

- **nginx**: HTTPS front end for all websites on port 443.
- **wordpress**: the website and its admin panel (php-fpm).
- **mariadb**: the database, reachable only from inside the Docker network.
- **redis**: the required WordPress object cache; reachable only inside Docker.
- **adminer**: a browser interface for managing the database.
- **goaccess**: website traffic and error statistics; no login required.
- **ftp**: upload, download and manage WordPress files using FTP over TLS.
- **static-website**: the personal portfolio; no login required.

## Start and stop

- Start (builds if needed): `make`
- Stop, keep containers: `make stop`, resume with `make start`
- Stop and remove containers: `make down`
- Remove everything including data: `make fclean`

## Access

Make sure `/etc/hosts` contains `127.0.0.1 mnestere.42.fr stats.mnestere.42.fr me.mnestere.42.fr adminer.mnestere.42.fr`.

- Website: https://mnestere.42.fr
- Admin panel: https://mnestere.42.fr/wp-admin
- Traffic dashboard: https://stats.mnestere.42.fr
- Portfolio: https://me.mnestere.42.fr
- Database administration: https://adminer.mnestere.42.fr

The browser warns about the certificate because it is self-signed; accept it.

## Credentials

- Usernames and the domain are in `srcs/.env` (`WP_ADMIN_USER`, `WP_USER`, ...).
- Passwords are files in `secrets/` (`wp_admin_password.txt`, `wp_user_password.txt`, `db_*_password.txt`). `make` generates any that are missing or empty.
- Neither `srcs/.env` nor `secrets/` is committed to git. Editing a secret file does not update an existing database or WordPress account. Change existing passwords through WordPress or MariaDB and update the matching secret/configuration. For a disposable reset only, `make fclean && make` recreates the installation and permanently deletes existing site data.

## Check that everything runs

- `make ps`: all eight containers should be `Up`, mariadb, redis, wordpress, nginx and ftp `healthy`.
- `make logs`: no errors from the entrypoint scripts.
- `curl -k https://mnestere.42.fr`: returns the WordPress page.
- `curl http://mnestere.42.fr` fails: HTTP port 80 is not published.

## Traffic dashboard

Open the statistics URL and visit a few pages on the main website. The report updates through its built-in WebSocket connection and shows requests, response codes, traffic and browser information. Statistics begin with traffic logged after GoAccess was added. Dashboard traffic is excluded from the report.

`make down` keeps logs and reports. `make fclean` permanently deletes them along with the database and WordPress files. If using a browser outside the VM, map all four hostnames to the VM's reachable IP and forward HTTPS as needed.

## Redis cache

WordPress requires Redis to start and to serve requests. If WordPress reports a Redis connection error, check `make ps` and `docker compose -f srcs/docker-compose.yml logs redis wordpress`. Start Redis again with `docker compose -f srcs/docker-compose.yml up -d redis`; WordPress requests recover when the cache is reachable. Redis contains disposable cached values, so losing its cache does not delete website data.

## Database administration

Open https://adminer.mnestere.42.fr and select MySQL. Enter server `mariadb`, the `MARIADB_ADMIN_USER` username from `srcs/.env`, the password from `secrets/db_admin_password.txt`, and the `MARIADB_DATABASE` database name. This is a database account, separate from your WordPress login. The root account accepts local database connections only.

## FTP file access

In FileZilla or another FTP client, use:

| Setting | Value |
|---|---|
| Protocol | FTP |
| Encryption | Require explicit FTP over TLS |
| Host | `mnestere.42.fr`, or the VM's reachable address |
| Port | `21` |
| Transfer mode | Passive |
| Username | `FTP_USER` from `srcs/.env` (default `ftp_user`) |
| Password | Contents of `secrets/ftp_password.txt` |

Accept the project's self-signed certificate. The FTP root is the WordPress directory, shared with the running site. Uploaded files are owned by the same user ID as WordPress, so both services can edit them. Changing or deleting website files through FTP changes the live site.

Inside the VM, the default `FTP_PASV_ADDRESS=127.0.0.1` works. For another machine, set it to the address reachable by that FTP client and recreate FTP. Open or forward TCP port 21 and ports 21100–21104; keep passive port numbers identical on both sides of any forwarding rule.

To change the FTP password, edit its secret file and run `docker compose -f srcs/docker-compose.yml up -d --force-recreate --no-deps ftp`. Unlike initialized database accounts, the FTP account password is applied on every container start. Files survive FTP container recreation and `make down`; `make fclean` deletes the shared WordPress volume.
