FROM python:3.12.2-slim as build

RUN pip3 install poetry

COPY . ./

# Install project dependencies using Poetry
RUN poetry install --no-interaction --no-dev --no-root

# Build and install the project
RUN poetry build

FROM python:3.12.2-alpine as final

COPY --from=build ./dist/*.whl .

RUN pip install *.whl

USER nobody

ENV ATILS_LOG_LEVEL=INFO

