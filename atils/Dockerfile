FROM python:3.12-slim as build

RUN pip3 install poetry

COPY . ./

# Install project dependencies using Poetry
RUN poetry install --no-interaction --no-dev --no-root

# Build and install the project
RUN poetry build

FROM python:3.12-slim as final

COPY --from=build ./dist/*.whl .

RUN pip install *.whl && rm *.whl

USER nobody

ENV ATILS_LOG_LEVEL=INFO

