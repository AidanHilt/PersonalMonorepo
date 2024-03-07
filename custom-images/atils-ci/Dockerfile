FROM ubuntu:22.04

RUN apt-get update && \
    apt-get install -y git python3 python3-pip apt-transport-https ca-certificates curl gnupg-agent software-properties-common && \
    apt-get install ca-certificates curl && \
    install -m 0755 -d /etc/apt/keyrings && \
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc && \
    chmod a+r /etc/apt/keyrings/docker.asc

RUN echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
    $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
    tee /etc/apt/sources.list.d/docker.list > /dev/null && \
    apt-get update && \
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

RUN pip3 install poetry

# Clone the repository
RUN git clone https://github.com/AidanHilt/PersonalMonorepo.git

# Change working directory to the "atils" directory
WORKDIR /PersonalMonorepo/atils

# Install project dependencies using Poetry
RUN poetry install --no-interaction

# Build and install the project
RUN poetry build && \
    pip3 install dist/*.whl

<<<<<<< HEAD
USER nobody

=======
<<<<<<< HEAD
USER nobody

=======
>>>>>>> b6aeb220957caa23e70198bfd9df6b9773d9730e
>>>>>>> 4e3f5e6879dab17d96018a9ce5f4b529967378e0
# Set the entrypoint to run "atils --version"
ENTRYPOINT ["atils", "--version"]