#!/bin/bash

#include printing-and-output
#include args-and-help

set -euo pipefail

args_description "Purges the nix store maximally"
args_example "$(basename "$0")"

args_parse "$@" || {
  rc=$?
  exit "$(args_rc "$rc")"
}

nix-collect-garbage -d 
nix-store --gc 
nix-store --optimise
