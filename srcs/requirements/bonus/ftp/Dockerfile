FROM debian:bookworm-slim

RUN apt-get update && \
    apt-get install -y --no-install-recommends vsftpd gettext-base && \
    rm -rf /var/lib/apt/lists/* && \
    mkdir -p /run/vsftpd/empty /var/www/html && \
    printf '/usr/sbin/nologin\n' >> /etc/shells

COPY requirements/bonus/ftp/conf/vsftpd.conf.template /etc/vsftpd.conf.template
COPY scripts/entrypoint-lib.sh /usr/local/lib/entrypoint-lib.sh
COPY requirements/bonus/ftp/tools/docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

EXPOSE 21 21100-21104
ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
CMD ["vsftpd", "/etc/vsftpd.conf"]
