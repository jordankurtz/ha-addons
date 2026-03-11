ARG BUILD_FROM=ghcr.io/home-assistant/aarch64-base-debian:bookworm

FROM ${BUILD_FROM}

ARG READSB_VERSION=dev
ARG TAR1090_VERSION=master
ARG MLAT_CLIENT_VERSION=master
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

# Install tar1090 web UI
RUN set -ex && \
    git clone --branch ${TAR1090_VERSION} --depth 1 \
        https://github.com/wiedehopf/tar1090.git /tmp/tar1090 && \
    mkdir -p /usr/local/share/tar1090/html && \
    cp -r /tmp/tar1090/html/* /usr/local/share/tar1090/html/ && \
    rm -rf /tmp/tar1090

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

COPY gpsd_client.py /usr/local/bin/gpsd_client
RUN chmod a+x /usr/local/bin/gpsd_client

COPY run.sh /
RUN chmod a+x /run.sh

CMD [ "/run.sh" ]
