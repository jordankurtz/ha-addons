ARG BUILD_FROM=ghcr.io/home-assistant/aarch64-base-debian:bookworm

FROM ${BUILD_FROM}

RUN apt-get update && apt-get install -y --no-install-recommends \
    gpsd \
    gpsd-clients \
    curl \
    jq \
    && rm -rf /var/lib/apt/lists/*

COPY run.sh /
RUN chmod a+x /run.sh

CMD [ "/run.sh" ]
