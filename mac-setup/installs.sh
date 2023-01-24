#!/bin/zsh
# sh -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
# sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"


#TODO add setup for Syncthing, and automatically update wallpapers

echo 'source <(kubectl completion zsh)' >>~/.zshrc
echo 'alias k=kubectl' >>~/.zshrc
echo 'complete -F __start_kubectl ks' >>~/.zshrc


#TODO Add automation for using fingerprint for sudo



source ~/.zshrc