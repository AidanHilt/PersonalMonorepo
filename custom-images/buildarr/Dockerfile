FROM python:3.11 as builder

RUN git clone https://github.com/AidanHilt/buildarr-jellyseerr && \
    python -m pip install poetry

RUN cd buildarr-jellyseerr && \
    poetry install && poetry build

FROM callum027/buildarr

COPY --from=builder buildarr-jellyseerr/dist /dist

RUN python -m pip uninstall buildarr-jellyseerr[sonarr,radarr] -y && \
    python -m pip install wheel && \
    python -m pip install /dist/buildarr_jellyseerr-0.3.3-py3-none-any.whl && \
    rm -r /dist