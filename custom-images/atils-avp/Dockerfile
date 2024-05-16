FROM registry.access.redhat.com/ubi8 as download-tool

RUN curl -L https://github.com/argoproj-labs/argocd-vault-plugin/releases/download/v$1.17.0/argocd-vault-plugin_1.17.0_linux_amd64 -o argocd-vault-plugin

FROM quay.io/argoproj/argocd:latest

COPY --from=download-tool argocd-vault-plugin /usr/local/bin/argocd-vault-plugin

USER root

RUN chmod +x /usr/local/bin/argocd-vault-plugin

USER argocd