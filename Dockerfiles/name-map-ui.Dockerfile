FROM alpine:3.17

# Copyright (c) 2023 Battelle Energy Alliance, LLC.  All rights reserved.
LABEL maintainer="malcolm@inl.gov"
LABEL org.opencontainers.image.authors='malcolm@inl.gov'
LABEL org.opencontainers.image.url='https://github.com/idaholab/Malcolm'
LABEL org.opencontainers.image.documentation='https://github.com/idaholab/Malcolm/blob/main/README.md'
LABEL org.opencontainers.image.source='https://github.com/idaholab/Malcolm'
LABEL org.opencontainers.image.vendor='Idaho National Laboratory'
LABEL org.opencontainers.image.title='ghcr.io/idaholab/malcolm/name-map-ui'
LABEL org.opencontainers.image.description='Malcolm container providing a user interface for mapping names to network hosts and subnets'

ARG DEFAULT_UID=1000
ARG DEFAULT_GID=1000
ENV DEFAULT_UID $DEFAULT_UID
ENV DEFAULT_GID $DEFAULT_GID
ENV PUSER "nginxsrv"
ENV PGROUP "nginxsrv"
ENV PUSER_PRIV_DROP true
ENV PUSER_CHOWN "/var/www/html;/var/lib/nginx;/var/log/nginx"

ENV TERM xterm

ENV JQUERY_VERSION 1.6.4
ENV LISTJS_VERSION v1.5.0

RUN apk update --no-cache && \
    apk upgrade --no-cache && \
    apk --no-cache add bash php81 php81-fpm php81-mysqli php81-json php81-openssl php81-curl php81-fileinfo \
    php81-zlib php81-xml php81-phar php81-intl php81-dom php81-xmlreader php81-ctype php81-session \
    php81-mbstring php81-gd nginx supervisor curl inotify-tools file psmisc rsync shadow openssl tini

COPY name-map-ui/config/nginx.conf /etc/nginx/nginx.conf
COPY name-map-ui/config/fpm-pool.conf /etc/php81/php-fpm.d/www.conf
COPY name-map-ui/config/php.ini /etc/php81/conf.d/custom.ini
COPY name-map-ui/config/supervisord.conf /etc/supervisord.conf
COPY name-map-ui/config/supervisor_logstash_ctl.conf /etc/supervisor/logstash/supervisord.conf
COPY name-map-ui/config/supervisor_netbox_ctl.conf /etc/supervisor/netbox/supervisord.conf
COPY name-map-ui/scripts/*.sh /usr/local/bin/

RUN curl -sSL -o /tmp/jquery.min.js "https://code.jquery.com/jquery-${JQUERY_VERSION}.min.js" && \
      curl -sSL -o /tmp/list.min.js "https://raw.githubusercontent.com/javve/list.js/${LISTJS_VERSION}/dist/list.min.js" && \
    rm -rf /etc/nginx/conf.d/default.conf /var/www/html/* && \
    mkdir -p /var/www/html/upload /var/www/html/maps && \
    cd /var/www/html && \
    mv /tmp/jquery.min.js /tmp/list.min.js ./ && \
    chmod 644 ./jquery.min.js ./list.min.js && \
    ln -s . name-map-ui && \
    addgroup -g ${DEFAULT_GID} ${PGROUP} ; \
    adduser -D -H -u ${DEFAULT_UID} -h /var/www/html -s /sbin/nologin -G ${PGROUP} -g ${PUSER} ${PUSER} ; \
    addgroup ${PUSER} nginx ; \
    addgroup ${PUSER} shadow ; \
    addgroup ${PUSER} tty ; \
    addgroup nginx tty ; \
    chown -R ${PUSER}:${PGROUP} /var/www/html && \
    chown -R ${PUSER}:${PGROUP} /var/lib/nginx && \
    chown -R ${PUSER}:${PGROUP} /var/log/nginx && \
    chmod 755 /usr/local/bin/*.sh

VOLUME /var/www/html

WORKDIR /var/www/html

ADD shared/bin/docker-uid-gid-setup.sh /usr/local/bin/
COPY name-map-ui/site/ /var/www/html/
COPY docs/images/logo/Malcolm_banner.png /var/www/html/
COPY docs/images/favicon/favicon.ico /var/www/html/

EXPOSE 8080

ENTRYPOINT ["/sbin/tini", "--", "/usr/local/bin/docker-uid-gid-setup.sh"]

CMD ["/usr/bin/supervisord", "-c", "/etc/supervisord.conf", "-n"]


# to be populated at build-time:
ARG BUILD_DATE
ARG MALCOLM_VERSION
ARG VCS_REVISION

LABEL org.opencontainers.image.created=$BUILD_DATE
LABEL org.opencontainers.image.version=$MALCOLM_VERSION
LABEL org.opencontainers.image.revision=$VCS_REVISION
