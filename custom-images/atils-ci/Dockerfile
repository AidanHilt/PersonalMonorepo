FROM alpine:latest

# Install necessary dependencies
RUN apk update && \
    apk add --no-cache git python3 py3-pip docker poetry

# Clone the repository
RUN git clone https://github.com/AidanHilt/PersonalMonorepo.git

# Change working directory to the "atils" directory
WORKDIR /PersonalMonorepo/atils

# Install project dependencies using Poetry
RUN poetry install --no-interaction

# Build and install the project
RUN poetry build && \
    pip3 install dist/*.whl

# Set the entrypoint to run "atils --version"
ENTRYPOINT ["atils", "--version"]