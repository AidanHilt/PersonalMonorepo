#!/bin/zsh
# Install Nix
curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install

/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

/nix/var/nix/profiles/default/bin/nix-build https://github.com/LnL7/nix-darwin/archive/master.tar.gz -A installer

/nix/var/nix/profiles/default/bin/nix-channel --add http://nixos.org/channels/nixpkgs-unstable nixpkgs
/nix/var/nix/profiles/default/bin/nix-channel --update

./result/bin/darwin-installer

mkdir -p ~/.config/nix-darwin

git clone https://github.com/AidanHilt/PersonalMonorepo.git
(cd PersonalMonorepo && pre-commit install)

hostnames=("Aidans-Macbook-Pro", "hyperion")

# Print available options
echo "\nAvailable hostnames:"
i=1
for hostname in "$hostnames[@]"; do
  echo "${i}) ${hostname}"
  i=$((i+1))
done

# Get user selection with input validation
while true; do
  echo -n "\nSelect hostname (1-${#hostnames[@]}): "
  read selection
  index=$((selection-1))

  # Check if input is a number and within valid range
  if [[ "$selection" =~ ^[0-9]+$ ]] && [ "$selection" -ge 1 ] && [ "$selection" -le ${#hostnames[@]} ]; then
    selected_hostname=${hostnames[@]:0:1}
    echo "\nYou selected: $selected_hostname"
    break
  else
    echo "Invalid selection. Please enter a number between 1 and ${#hostnames[@]}"
  fi
done

sudo mv /etc/auto_master /etc/auto_master.before-nix-darwin
mkdir ~/Library/Application\ Support/Firefox
touch ~/Library/Application\ Support/Firefox/profiles.ini


echo "darwin-rebuild switch --flake ~/PersonalMonorepo/nix/mac-setup#$selected_hostname" | pbcopy

echo "This script has finished running. Please open a new terminal, and then CMD+V to run the nix command that will run the initial nix setup"
echo "Once the nix installation has been completed, you can open a new terminal and run 'finish-setup' to finalize the setup"