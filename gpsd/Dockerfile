ARG BUILD_FROM=ghcr.io/home-assistant/aarch64-base-debian:bookworm

FROM ${BUILD_FROM}

ARG GPSD_VERSION=release-3.27.5

# Build gpsd from source
RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential \
        git \
        scons \
        pkg-config \
    && git clone --depth 1 --branch "${GPSD_VERSION}" \
        https://gitlab.com/gpsd/gpsd.git /tmp/gpsd \
    && cd /tmp/gpsd \
    && scons prefix=/usr python=no ipv6=no \
    && scons prefix=/usr python=no ipv6=no install \
    && rm -rf /tmp/gpsd \
    && apt-get purge -y build-essential git scons pkg-config \
    && apt-get autoremove -y \
    && rm -rf /var/lib/apt/lists/*

# Runtime dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
        curl \
        jq \
        python3 \
    && rm -rf /var/lib/apt/lists/*

COPY gpsd_client.py /usr/local/bin/gpsd_client
RUN chmod a+x /usr/local/bin/gpsd_client

RUN mkdir -p /usr/share/gpsd-ui
COPY index.html /usr/share/gpsd-ui/index.html
COPY server.py /usr/share/gpsd-ui/server.py

COPY run.sh /
RUN chmod a+x /run.sh

CMD [ "/run.sh" ]
