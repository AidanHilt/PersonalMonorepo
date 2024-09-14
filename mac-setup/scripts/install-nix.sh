#!/bin/zsh

# Install nix itself
sh <(curl -L https://nixos.org/nix/install)

# Install nix-darwin
nix-build https://github.com/LnL7/nix-darwin/archive/master.tar.gz -A installer
./result/bin/darwin-installer