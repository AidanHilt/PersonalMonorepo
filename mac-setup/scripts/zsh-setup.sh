#!/bin/zsh

# Install Oh My Zsh
# check if oh-my-zsh is installed
if [ -d ~/.oh-my-zsh ]; then
    echo "Oh My Zsh is already installed, skipping installation"
else
    echo "Installing Oh My Zsh"
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
fi

# Install zsh powerlevel10k
git clone --depth=1 https://github.com/romkatv/powerlevel10k.git ${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/powerlevel10k