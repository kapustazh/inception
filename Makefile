LOGIN    := mnestere
DOMAIN   := $(shell sed -n 's/^DOMAIN_NAME=//p' srcs/.env 2>/dev/null)
DATA_DIR := /home/$(LOGIN)/data
CERT_DIR := secrets/certs
COMPOSE  := docker compose -f srcs/docker-compose.yml
SECRETS  := db_root_password db_admin_password db_wp_user_password wp_admin_password wp_user_password

export DATA_DIR

all: up

up: check-env secrets cert
	@mkdir -p $(DATA_DIR)/mariadb $(DATA_DIR)/wordpress $(DATA_DIR)/nginx-logs $(DATA_DIR)/goaccess
	@for host in "$(DOMAIN)" "stats.$(DOMAIN)" "me.$(DOMAIN)"; do \
		getent hosts "$$host" >/dev/null || echo "WARNING: add '127.0.0.1 $$host' to /etc/hosts"; \
	done
	@$(COMPOSE) up -d --build

# fills only missing/empty secret files, never overwrites existing ones
secrets:
	@mkdir -p secrets
	@set -eu; for f in $(SECRETS); do \
		[ -s secrets/$$f.txt ] || { openssl rand -hex 16 > secrets/$$f.txt; echo "generated secrets/$$f.txt"; }; \
		chmod 600 secrets/$$f.txt; \
	done

check-env:
	@test -s srcs/.env || { echo "Copy srcs/.env.example to srcs/.env first" >&2; exit 1; }
	@test -n "$(DOMAIN)" || { echo "Set DOMAIN_NAME in srcs/.env" >&2; exit 1; }

cert: check-env
	@mkdir -p $(CERT_DIR)
	@if ! test -s $(CERT_DIR)/inception_nginx.key || \
	    ! openssl x509 -in $(CERT_DIR)/inception_nginx.crt -noout -checkhost "$(DOMAIN)" >/dev/null 2>&1 || \
	    ! openssl x509 -in $(CERT_DIR)/inception_nginx.crt -noout -checkhost "stats.$(DOMAIN)" >/dev/null 2>&1 || \
	    ! openssl x509 -in $(CERT_DIR)/inception_nginx.crt -noout -checkhost "me.$(DOMAIN)" >/dev/null 2>&1 || \
	    ! openssl x509 -in $(CERT_DIR)/inception_nginx.crt -noout -checkend 0 >/dev/null 2>&1; then \
		openssl req -x509 -nodes -newkey rsa:2048 -days 365 \
		-subj "/CN=$(DOMAIN)" -addext "subjectAltName=DNS:$(DOMAIN),DNS:stats.$(DOMAIN),DNS:me.$(DOMAIN)" \
		-keyout $(CERT_DIR)/inception_nginx.key -out $(CERT_DIR)/inception_nginx.crt || exit 1; \
	fi
	@chmod 600 $(CERT_DIR)/inception_nginx.key

down:
	@$(COMPOSE) down

stop:
	@$(COMPOSE) stop

start:
	@$(COMPOSE) start

logs:
	@$(COMPOSE) logs -f

ps:
	@$(COMPOSE) ps

clean:
	@$(COMPOSE) down --rmi all

# removes containers, images, volumes and the host data (db + site files)
fclean:
	@$(COMPOSE) down --rmi all -v
	@docker run --rm -v $(DATA_DIR):/data debian:bookworm-slim sh -c 'find /data -mindepth 1 -maxdepth 1 -exec rm -rf -- {} +'

re:
	@$(MAKE) fclean
	@$(MAKE) up

.PHONY: all up check-env secrets cert down stop start logs ps clean fclean re
