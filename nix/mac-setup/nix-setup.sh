#!/bin/zsh
# Install Nix
curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install

source /etc/zshrc

/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

nix-build https://github.com/LnL7/nix-darwin/archive/master.tar.gz -A installer

./result/bin/darwin-installer

mkdir -p ~/.config/nix-darwin
mkdir -p ~/.config/nixpkgs

config_content='
{
  packageOverrides = pkgs: {
    nur = import (builtins.fetchTarball {
      url = "https://github.com/nix-community/NUR/archive/master.tar.gz";
    }) {
      inherit pkgs;
    };
  };
}
'

# Check if config.nix already exists
if [[ -f ~/.config/nixpkgs/config.nix ]]; then
  # Check if the packageOverrides are already present
  if grep -q "packageOverrides" ~/.config/nixpkgs/config.nix; then
    echo "packageOverrides already exists in ~/.config/nixpkgs/config.nix"
    echo "Please manually update the file if you need to change the configuration."
  else
    # Append the new configuration to the existing file
    echo "$config_content" >> ~/.config/nixpkgs/config.nix
    echo "Updated ~/.config/nixpkgs/config.nix with the new packageOverrides configuration"
  fi
else
  # Create a new config.nix with the provided content
  echo "$config_content" > ~/.config/nixpkgs/config.nix
  echo "Created ~/.config/nixpkgs/config.nix with the packageOverrides configuration"
fi



