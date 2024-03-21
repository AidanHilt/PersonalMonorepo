FROM aidanhilt/atils:latest

USER root

SHELL ["/bin/bash", "-c"]

# Install all the apt packages we'll need
RUN apt-get update && \
    apt-get install -y python3 pipx apt-transport-https ca-certificates curl gnupg-agent software-properties-common ca-certificates curl jq yq

# Get us ready for, then install Docker and buildx. This image runs on GH action runners, so we don't need to set up or enable buildx here
RUN install -m 0755 -d /etc/apt/keyrings && \
    curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc && \
    chmod a+r /etc/apt/keyrings/docker.asc && \
    echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian \
    $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
    tee /etc/apt/sources.list.d/docker.list > /dev/null && \
    apt-get update && \
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Install npm, yarn, and all that. We use this to build our Toolshed image
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - && \
    apt-get install -y nodejs && \
    corepack enable

# Install Helm, for building and publishing Helm charts
RUN curl https://baltocdn.com/helm/signing.asc | gpg --dearmor | tee /usr/share/keyrings/helm.gpg > /dev/null && \
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/helm.gpg] https://baltocdn.com/helm/stable/debian/ all main" | tee /etc/apt/sources.list.d/helm-stable-debian.list && \
    apt-get update && \
    apt-get install helm

RUN pip3 install poetry check-jsonschema

ENV ATILS_CI_ENV=true