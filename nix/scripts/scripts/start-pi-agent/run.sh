#!/bin/bash

#include printing-and-output
#include env-checks

set -euo pipefail

# EXE_nix is a flake runtime-dependency placeholder (see
# nix/scripts/IMPLEMENTERS.md's "Runtime dependencies" section) substituted
# at build time. The declaration below keeps shellcheck from flagging
# SC2154 without needing a disable directive.
: "${EXE_nix:=}" # runtime-dependency placeholder, substituted at build time
readonly NIX="${EXE_nix}"

# keepass-retrieve-secret is a sibling script in this flake (not a nixpkgs
# package), so it's relied on via PATH rather than the PKG_/EXE_ mechanism,
# same as other cross-script calls in this repo (e.g.
# nixos-remote-install calling nixos-key-retrieval).

require_monorepo

if [[ ! -d "${PERSONAL_MONOREPO_LOCATION}" ]]; then
  print_error "PERSONAL_MONOREPO_LOCATION ('${PERSONAL_MONOREPO_LOCATION}') is not a directory"
  exit 1
fi

print_debug "Retrieving GITHUB_TOKEN from KeePass"
github_token="$(keepass-retrieve-secret --secret-path "Internet/Github" --key-name "PI_GITHUB_TOKEN")"
if [[ -z "${github_token}" ]]; then
  print_error "Failed to retrieve GITHUB_TOKEN from KeePass"
  exit 1
fi

print_debug "Retrieving EXA_API_KEY from KeePass"
exa_api_key="$(keepass-retrieve-secret --secret-path "Internet/Personal Computers, Servers, and Services/Exa AI")"
if [[ -z "${exa_api_key}" ]]; then
  print_error "Failed to retrieve EXA_API_KEY from KeePass"
  exit 1
fi

readonly GITHUB_TOKEN="${github_token}"
readonly EXA_API_KEY="${exa_api_key}"

cd "${PERSONAL_MONOREPO_LOCATION}/nix/agentic-ai-stack"

print_status "Launching pi agent sandbox"

exec "${NIX}" run .#start-agent -- \
  --secret "GITHUB_TOKEN=${GITHUB_TOKEN}" \
  --secret "EXA_API_KEY=${EXA_API_KEY}" \
  --add "${PERSONAL_MONOREPO_LOCATION}" \
  "$@"
