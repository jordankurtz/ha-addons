ARG BUILD_FROM=ghcr.io/home-assistant/aarch64-base-debian:bookworm

FROM ${BUILD_FROM}

RUN apt-get update && apt-get install -y --no-install-recommends \
    gpsd \
    gpsd-clients \
    curl \
    jq \
    python3 \
    && rm -rf /var/lib/apt/lists/*

RUN mkdir -p /usr/share/gpsd-ui
COPY index.html /usr/share/gpsd-ui/index.html
COPY server.py /usr/share/gpsd-ui/server.py

COPY run.sh /
RUN chmod a+x /run.sh

CMD [ "/run.sh" ]
