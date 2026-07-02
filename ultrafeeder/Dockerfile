ARG BUILD_FROM=ghcr.io/home-assistant/aarch64-base-debian:bookworm

FROM ${BUILD_FROM}

ARG READSB_VERSION=v3.16.15
ARG TAR1090_VERSION=cbcf0260d99b29afb9fc00dc3271ac0e937b2819
ARG MLAT_CLIENT_VERSION=v0.4.2
ARG DUMP1090_VERSION=v9.0
ARG PIAWARE_BUILDER_VERSION=v9.0.1

# Install build + runtime dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    ca-certificates \
    cmake \
    debhelper \
    devscripts \
    git \
    pkg-config \
    autoconf \
    automake \
    patchelf \
    wget \
    python3 \
    python3-dev \
    python3-pip \
    python3-setuptools \
    python3-build \
    python3-venv \
    python3-wheel \
    librtlsdr-dev \
    libncurses-dev \
    zlib1g-dev \
    libzstd-dev \
    libboost-filesystem-dev \
    libboost-program-options-dev \
    libboost-regex-dev \
    libboost-system-dev \
    libssl-dev \
    tcl-dev \
    tcl-tls \
    tcllib \
    tclx8.4 \
    itcl3 \
    libtcl8.6 \
    lighttpd \
    curl \
    jq \
    procps \
    librtlsdr0 \
    net-tools \
    openssl \
    && rm -rf /var/lib/apt/lists/*

# Build readsb from source
RUN set -ex && \
    git clone --branch ${READSB_VERSION} --depth 1 \
        https://github.com/wiedehopf/readsb.git /tmp/readsb && \
    cd /tmp/readsb && \
    make RTLSDR=yes OPTIMIZE="-O2" && \
    cp readsb /usr/bin/readsb && \
    cp viewadsb /usr/bin/viewadsb && \
    rm -rf /tmp/readsb

# Install tar1090 web UI (pinned to a commit SHA — upstream has no version tags)
RUN set -ex && \
    git init /tmp/tar1090 && cd /tmp/tar1090 && \
    git remote add origin https://github.com/wiedehopf/tar1090.git && \
    git fetch --depth 1 origin ${TAR1090_VERSION} && \
    git checkout FETCH_HEAD && \
    mkdir -p /usr/local/share/tar1090/html && \
    cp -r /tmp/tar1090/html/* /usr/local/share/tar1090/html/ && \
    cd / && rm -rf /tmp/tar1090

# Install aircraft database from dump1090 (for PiAwareMobile API compatibility)
RUN set -ex && \
    git clone --branch ${DUMP1090_VERSION} --depth 1 \
        https://github.com/flightaware/dump1090.git /tmp/dump1090 && \
    cp -r /tmp/dump1090/public_html/db /usr/local/share/tar1090/html/db && \
    rm -rf /tmp/dump1090

# Build mlat-client
RUN set -ex && \
    git clone --branch ${MLAT_CLIENT_VERSION} --depth 1 \
        https://github.com/wiedehopf/mlat-client.git /tmp/mlat-client && \
    cd /tmp/mlat-client && \
    python3 -m pip install . --break-system-packages && \
    rm -rf /tmp/mlat-client

# Build piaware using piaware_builder
RUN set -ex && \
    git clone --branch ${PIAWARE_BUILDER_VERSION} --depth 1 \
        https://github.com/flightaware/piaware_builder.git /tmp/piaware_builder && \
    cd /tmp/piaware_builder && \
    ./sensible-build.sh bookworm && \
    cd /tmp/piaware_builder/package-bookworm && \
    dpkg-buildpackage -b --no-sign && \
    cd /tmp/piaware_builder && \
    dpkg -i piaware*.deb && \
    rm -rf /tmp/piaware_builder

# Configure lighttpd
RUN mkdir -p /etc/lighttpd/conf-enabled \
             /var/log/lighttpd \
             /run/lighttpd

COPY lighttpd.conf /etc/lighttpd/lighttpd.conf

# Create required directories
RUN mkdir -p \
    /run/readsb \
    /run/piaware \
    /data/ultrafeeder \
    /var/log/piaware \
    /etc/piaware

# Remove build dependencies to reduce image size
RUN apt-get purge -y --auto-remove \
    build-essential \
    cmake \
    debhelper \
    devscripts \
    git \
    pkg-config \
    autoconf \
    automake \
    patchelf \
    wget \
    python3-dev \
    python3-venv \
    librtlsdr-dev \
    libncurses-dev \
    zlib1g-dev \
    libzstd-dev \
    libboost-filesystem-dev \
    libboost-program-options-dev \
    libboost-regex-dev \
    libboost-system-dev \
    libssl-dev \
    tcl-dev \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Reinstall runtime libraries removed by auto-remove
RUN apt-get update \
    && apt-get install -y --no-install-recommends libncurses6 libzstd1 \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

COPY gpsd_client.py /usr/local/bin/gpsd_client
RUN chmod a+x /usr/local/bin/gpsd_client

COPY run.sh /
RUN chmod a+x /run.sh

CMD [ "/run.sh" ]
