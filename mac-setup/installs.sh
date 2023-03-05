#!/bin/zsh
# This covers auto complete for kubectl, along with setting the 'k' alias
# echo 'source <(kubectl completion zsh)' >>~/.zshrc
# echo 'alias k=kubectl' >>~/.zshrc
# echo 'complete -F __start_kubectl ks' >>~/.zshrc

# TODO add setup for Syncthing, and automatically update wallpapers

# TODO Add automation for using fingerprint for sudo

# TODO pare down applications allowed to run in the background to the bare minimum

# This covers installing a command line wrapper for ChatGPT
pip3 install setuptools pytest-playwright
playwright install firefox

pip3 install git+https://github.com/mmabrouk/chatgpt-wrapper
chatgpt install


source ~/.zshrc