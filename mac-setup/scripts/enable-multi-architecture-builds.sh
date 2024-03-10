#!/bin/zsh

# Install multi-arch builder for docker
docker buildx create --name multi-arch-builder --use
docker buildx install