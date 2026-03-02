ARG BUILD_FROM=ghcr.io/home-assistant/aarch64-base-debian:bookworm
ARG PIHOLE_VERSION=2026.02.0

# Stage 1: Extract Pi-hole components from official image
FROM pihole/pihole:${PIHOLE_VERSION} AS pihole-source

# Stage 2: Build on Home Assistant Debian base
FROM ${BUILD_FROM}

# Install runtime dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    nginx \
    sudo \
    coreutils \
    git \
    iproute2 \
    procps \
    libcap2 \
    libcap2-bin \
    libsqlite3-0 \
    curl \
    jq \
    && rm -rf /var/lib/apt/lists/*

# Copy Pi-hole FTL binary and strip file capabilities
# (file caps from the source image cause EPERM in HA's container security)
COPY --from=pihole-source /usr/bin/pihole-FTL /usr/bin/pihole-FTL
RUN setcap -r /usr/bin/pihole-FTL 2>/dev/null || true

# Copy Pi-hole scripts, utilities, and support files
COPY --from=pihole-source /usr/local/bin/pihole /usr/local/bin/pihole
COPY --from=pihole-source /opt/pihole/ /opt/pihole/
COPY --from=pihole-source /etc/.pihole/ /etc/.pihole/

# Copy Pi-hole web interface
COPY --from=pihole-source /var/www/html/ /var/www/html/

# Create pihole user and group
RUN groupadd -r pihole 2>/dev/null || true && \
    useradd -r -g pihole -d /etc/pihole -s /usr/sbin/nologin pihole 2>/dev/null || true

# Create required directories
RUN mkdir -p \
    /etc/pihole \
    /etc/dnsmasq.d \
    /var/log/pihole \
    /var/run/pihole \
    /data/pihole \
    /data/dnsmasq.d

# Copy nginx ingress configuration and remove default site
COPY nginx-ingress.conf /etc/nginx/conf.d/ingress.conf
RUN rm -f /etc/nginx/sites-enabled/default

# Copy run script
COPY run.sh /
RUN chmod a+x /run.sh

CMD [ "/run.sh" ]
