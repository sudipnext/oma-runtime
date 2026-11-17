# syntax=docker/dockerfile:1
# Agent37's dated base supplies Hermes, the chat gateway and browser/tool services.
FROM ghcr.io/agent37-platform/hermes-base:2026.11.12b@sha256:ecfb43565f7edb3b827b662a9b896d76171730ea5c23b646f9038d73c1832f31

USER root

LABEL org.opencontainers.image.title="OMA runtime" \
      org.opencontainers.image.description="Hermes and a local WordPress test site for Agent37" \
      org.opencontainers.image.source="https://github.com/sudipnext/oma-runtime"

# Do not start distro services while building; all runtime services run as node.
RUN printf '#!/bin/sh\nexit 101\n' > /usr/sbin/policy-rc.d \
    && chmod 0755 /usr/sbin/policy-rc.d \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
       supervisor apache2 libapache2-mod-php8.2 \
       php8.2-cli php8.2-mysql php8.2-curl php8.2-gd php8.2-mbstring \
       php8.2-xml php8.2-zip php8.2-intl mariadb-server mariadb-client \
    && a2enmod rewrite \
    && rm -rf /var/lib/apt/lists/*

# Verify downloads and keep seeds outside the persistent /home/node mount.
RUN curl -fsSL https://github.com/wp-cli/wp-cli/releases/download/v2.12.0/wp-cli-2.12.0.phar -o /usr/local/bin/wp \
    && echo 'ce34ddd838f7351d6759068d09793f26755463b4a4610a5a5c0a97b68220d85c  /usr/local/bin/wp' | sha256sum -c - \
    && chmod 0755 /usr/local/bin/wp \
    && curl -fsSL https://downloads.wordpress.org/release/wordpress-7.1.4.tar.gz -o /tmp/wordpress.tar.gz \
    && echo '881e53a4681ff2cd911651b11cccdede5ae477ddf0765af5d6a1a8b219a1d835  /tmp/wordpress.tar.gz' | sha256sum -c - \
    && mkdir -p /opt/oma \
    && tar -xzf /tmp/wordpress.tar.gz -C /opt/oma \
    && rm /tmp/wordpress.tar.gz \
    && mv /usr/local/bin/entrypoint.sh /opt/oma/hermes-entrypoint.sh

COPY apache2.conf supervisord.conf bootstrap.py /opt/oma/
COPY --chmod=0755 entrypoint.sh mariadb.sh healthcheck.sh /opt/oma/

# Leave the inherited ENTRYPOINT path intact and retain the upstream supervisor
# as a child, alongside MariaDB and Apache; do not replace Hermes with WordPress.
RUN ln -s /opt/oma/entrypoint.sh /usr/local/bin/entrypoint.sh \
    && printf 'memory_limit=128M\nexpose_php=Off\n' > /etc/php/8.2/apache2/conf.d/99-oma.ini \
    && /usr/bin/python3 -m py_compile /opt/oma/bootstrap.py

EXPOSE 8081
HEALTHCHECK --interval=15s --timeout=10s --start-period=120s --retries=4 CMD ["/opt/oma/healthcheck.sh"]

USER node
