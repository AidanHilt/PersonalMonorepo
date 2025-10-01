FROM python:3.11 AS builder

# Installing our builds tools, I think we need both PDM and Poetry

RUN python -m pip install pdm poetry

# Rebuildarr's fork of buildarr

RUN git clone https://github.com/rebuildarr/buildarr.git && \
    cd buildarr && \
    pdm build

# Our forks of Rebuildarr's module forks

RUN git clone https://github.com/AidanHilt/buildarr-radarr.git && \
    cd buildarr-radarr && \
    poetry install && poetry build

RUN git clone https://github.com/AidanHilt/buildarr-sonarr.git && \
    cd buildarr-sonarr && \
    pdm build

RUN git clone https://github.com/AidanHilt/buildarr-prowlarr.git && \
    cd buildarr-prowlarr && \
    poetry install && poetry build

RUN git clone https://github.com/AidanHilt/buildarr-jellyseerr && \
    cd buildarr-jellyseerr && \
    poetry install && poetry build

FROM python:3.11-alpine

COPY --from=builder buildarr/dist /dist
COPY --from=builder buildarr-radarr/dist /dist
COPY --from=builder buildarr-sonarr/dist /dist
COPY --from=builder buildarr-prowlarr/dist /dist
COPY --from=builder buildarr-jellyseerr/dist /dist

COPY entrypoint.sh /bootstrap.sh

ENV PUID=1000
ENV PGID=1000

RUN apk add su-exec tzdata git && \
    python -m pip install wheel && \
    for f in /dist/*.whl; do python -m pip install "$f"; done && \
    rm -r /dist && \
    chmod +x /bootstrap.sh

# Set the Buildarr configuration folder as the default Docker container working folder.
WORKDIR /config

# Setup the Docker image entry point to bootstrap packages and start Buildarr daemon.
ENTRYPOINT ["/bootstrap.sh"]
CMD ["daemon"]
