ARG BUILD_FROM=ghcr.io/home-assistant/aarch64-base-debian:bookworm

FROM ${BUILD_FROM}

ARG PIAWARE_BUILDER_VERSION=v10.2
ARG DUMP1090_VERSION=v10.2

# Install build dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    ca-certificates \
    cmake \
    debhelper \
    devscripts \
    git \
    libbladerf-dev \
    libboost-filesystem-dev \
    libboost-program-options-dev \
    libboost-regex-dev \
    libboost-system-dev \
    libhackrf-dev \
    liblimesuite-dev \
    libncurses-dev \
    librtlsdr-dev \
    libsoapysdr-dev \
    libssl-dev \
    libtcl8.6 \
    libz-dev \
    autoconf \
    automake \
    net-tools \
    openssl \
    patchelf \
    pkg-config \
    python3 \
    python3-build \
    python3-dev \
    python3-pip \
    python3-setuptools \
    python3-venv \
    python3-wheel \
    tcl-dev \
    tcl-tls \
    tcllib \
    tclx8.4 \
    itcl3 \
    lighttpd \
    wget \
    procps \
    curl \
    jq \
    && rm -rf /var/lib/apt/lists/*

# Build dump1090-fa from source
RUN set -ex && \
    git clone --branch ${DUMP1090_VERSION} --depth 1 \
        https://github.com/flightaware/dump1090.git /tmp/dump1090 && \
    cd /tmp/dump1090 && \
    make BLADERF=no HACKRF=no LIMESDR=no RTLSDR=yes && \
    cp dump1090 /usr/bin/dump1090-fa && \
    mkdir -p /usr/share/skyaware/html && \
    cp -r public_html/* /usr/share/skyaware/html/ 2>/dev/null || true && \
    rm -rf /tmp/dump1090

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

# Configure lighttpd for SkyAware
RUN mkdir -p /etc/lighttpd/conf-enabled \
             /var/log/lighttpd \
             /run/lighttpd

COPY lighttpd.conf /etc/lighttpd/lighttpd.conf

# Create required directories
RUN mkdir -p \
    /run/dump1090-fa \
    /run/piaware \
    /data/piaware \
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
    python3-dev \
    python3-venv \
    libssl-dev \
    libz-dev \
    patchelf \
    wget \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Copy run script
COPY run.sh /
RUN chmod a+x /run.sh

CMD [ "/run.sh" ]
