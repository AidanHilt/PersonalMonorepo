# Install Nix
curl -L https://nixos.org/nix/install | sh

mkdir -p ~/.config/nix/
echo "experimental-features = nix-command flakes" > ~/.config/nix/nix.conf

exec zsh -c "nix-build https://github.com/LnL7/nix-darwin/archive/master.tar.gz -A installer; ./result/bin/darwin-installer"

mkdir -p ~/.config/nix-darwin

# Replace this with some kind of curl, but for now this will work
cp /Volumes/My Shared Files/nixosShare/config/flake.nix ~/.config/nix-darwin/
