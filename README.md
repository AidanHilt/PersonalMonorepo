# Personal Monorepo
This monorepo contains most of my personal projects, many of which focus on running a kubernetes cluster at home with rigorous IaC and GitOps standards. This document provides an overview of the projects in the repository, and serves as a table of contents for these projects' own READMEs and IMPLEMENTERS files. 

## Documentation Conventions

READMEs describe how to *use* a project. IMPLEMENTERS.md describes how to *modify or read* it. Commits follow conventional commits (via the kommit CLI in nix/scripts). 

## Projects

| Path | Description |
| --- | --- |
| [nix/mono-flake](nix/mono-flake/README.md) | NixOS, nix-darwin and home-manager configuration for all hosts/machines. |
| [nix/scripts](nix/scripts/README.md) | A flake of ~80 bash/go utility scripts (`app-creator-*`, `argocd-*`, `nixos-*`, `vault-*`, `kommit`, `tg`, and more), used across the rest of the repository. |
| [nix/terraform](nix/terraform/README.md) | Nix modules that generate Terraform (via terranix) for Authentik, SeaweedFS, Vault, and Vault PKI. The generated modules are run by `terragrunt/`, and `terraform/staging-cluster-vm` is a plain Terraform module that creates VMs for a staging cluster. |
| [nix/custom-images](nix/custom-images/README.md) | Nix-built container images (e.g. it-tools, transmission). |
| [kubernetes/helm-charts](kubernetes/helm-charts/README.md) | Application and cluster-resource Helm charts, built on the bjw-s common library chart. |
| [kubernetes](kubernetes/README.md) | Cluster configurations, as well as helm charts. |
| [nix/agentic-ai-stack](nix/agentic-ai-stack/README.md) | A Nix-built Docker-compose sandbox for the Pi coding agent. |
| [windows-setup](windows-setup/README.md) | Personal PowerShell/Windows setup scripts. |
| `custom-images/` | **Deprecated / legacy.** Dockerfile-based container images, pending removal in favor of `nix/custom-images`. |


## For contributors and agents

If you're modifying or reading source rather than just using a project, see
[IMPLEMENTERS.md](IMPLEMENTERS.md). 
