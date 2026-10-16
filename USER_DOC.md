# User documentation

## Services

- **nginx**: HTTPS front end on port 443, the only exposed service.
- **wordpress**: the website and its admin panel (php-fpm).
- **mariadb**: the database, reachable only from inside the Docker network.
- **goaccess**: website traffic and error statistics; no login required.
- **static-website**: the personal portfolio; no login required.

## Start and stop

- Start (builds if needed): `make`
- Stop, keep containers: `make stop`, resume with `make start`
- Stop and remove containers: `make down`
- Remove everything including data: `make fclean`

## Access

Make sure `/etc/hosts` contains `127.0.0.1 mnestere.42.fr stats.mnestere.42.fr me.mnestere.42.fr`.

- Website: https://mnestere.42.fr
- Admin panel: https://mnestere.42.fr/wp-admin
- Traffic dashboard: https://stats.mnestere.42.fr
- Portfolio: https://me.mnestere.42.fr

The browser warns about the certificate because it is self-signed; accept it.

## Credentials

- Usernames and the domain are in `srcs/.env` (`WP_ADMIN_USER`, `WP_USER`, ...).
- Passwords are files in `secrets/` (`wp_admin_password.txt`, `wp_user_password.txt`, `db_*_password.txt`). `make` generates any that are missing or empty.
- Neither `srcs/.env` nor `secrets/` is committed to git. Editing a secret file does not update an existing database or WordPress account. Change existing passwords through WordPress or MariaDB and update the matching secret/configuration. For a disposable reset only, `make fclean && make` recreates the installation and permanently deletes existing site data.

## Check that everything runs

- `make ps`: all five containers should be `Up`, mariadb and nginx `healthy`.
- `make logs`: no errors from the entrypoint scripts.
- `curl -k https://mnestere.42.fr`: returns the WordPress page.
- `curl http://mnestere.42.fr` fails: only port 443 is open.

## Traffic dashboard

Open the statistics URL and visit a few pages on the main website. The report updates through its built-in WebSocket connection and shows requests, response codes, traffic and browser information. Statistics begin with traffic logged after GoAccess was added. Dashboard traffic is excluded from the report.

`make down` keeps logs and reports. `make fclean` permanently deletes them along with the database and WordPress files. If using a browser outside the VM, map all three hostnames to the VM's reachable IP and forward HTTPS as needed.
