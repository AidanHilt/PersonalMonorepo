FROM alpine as download-tool

ARG TARGETARCH

RUN apk add --no-cache curl

RUN curl -L https://github.com/argoproj-labs/argocd-vault-plugin/releases/download/v1.17.0/argocd-vault-plugin_1.17.0_linux_$TARGETARCH -o /argocd-vault-plugin

FROM quay.io/argoproj/argocd:latest

COPY --from=download-tool /argocd-vault-plugin /usr/local/bin/argocd-vault-plugin

USER root

RUN chmod 775 /usr/local/bin/argocd-vault-plugin

USER argocd