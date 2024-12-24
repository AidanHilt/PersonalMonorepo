FROM python:3.11 AS builder

RUN git clone https://github.com/AidanHilt/buildarr-jellyseerr && \
    python -m pip install poetry

RUN cd buildarr-jellyseerr && \
    poetry install && poetry build

RUN git clone https://github.com/AidanHilt/buildarr-radarr

RUN cd buildarr-radarr && \
    poetry install && poetry build

RUN git clone https://github.com/AidanHilt/buildarr-sonarr.git && \
    python -m pip install pdm

RUN cd buildarr-sonarr && \
    pdm install && pdm build

FROM python:3.11-alpine

COPY --from=builder buildarr-jellyseerr/dist /dist
COPY --from=builder buildarr-radarr/dist /dist
COPY --from=builder buildarr-sonarr/dist /dist

RUN python -m pip install wheel && \
    for f in /dist/*.whl; do python -m pip install "$f"; done && \
    rm -r /dist && \
    python -m pip install buildarr==0.7.1 buildarr-prowlarr

# Set the Buildarr configuration folder as the default Docker container working folder.
WORKDIR /config

# Setup the Docker image entry point to bootstrap packages and start Buildarr daemon.
ENTRYPOINT ["/bootstrap.sh"]
CMD ["daemon"]
