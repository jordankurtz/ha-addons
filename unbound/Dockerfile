ARG BUILD_FROM=ghcr.io/home-assistant/aarch64-base-debian:bookworm

FROM ${BUILD_FROM}

# Install unbound and dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    unbound \
    dns-root-data \
    ca-certificates \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Create required directories
RUN mkdir -p \
    /data/unbound \
    /var/run/unbound

# Copy run script
COPY run.sh /
RUN chmod a+x /run.sh

CMD [ "/run.sh" ]
