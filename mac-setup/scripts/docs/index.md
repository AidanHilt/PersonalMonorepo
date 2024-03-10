# Mac Configuration Scripts

These are scripts that help setup different things for a MacOS device. They are all written assuming zsh, but you don't need to have any other extensions.

1. `fingerprint-sudo.sh`: Sets up using fingerprints to authenticate with sudo.
2. `homebrew-setup.sh`: Literally just the install command for [Homebrew](https://brew.sh/).
3. `misc.sh`: Just handles some other configurations that I like. Right now, it just shows all files in Finder
4. `zsh-setup.sh`: Sets up zsh just the way I like it. That means installing oh-my-zsh, and then installing [powerlevel10k](https://github.com/romkatv/powerlevel10k)
5. `enable-multi-architecture-builds.sh`: We want to be able to build for ARM and x86 when making Docker images, so this script simply runs the pre-requisites