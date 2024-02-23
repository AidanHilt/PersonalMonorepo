# Mac Dotfiles

These are [dotfiles](https://wiki.archlinux.org/title/Dotfiles) used to configure programs on Mac. Some of them may be shared with other configuration setups, such as for Linux.

The configuration is managed using [stow](https://www.gnu.org/software/stow/). You can specify the entire paths of the directory where the files are stored, and where you want to install them to, but by running:

```stow stow --dir=$HOME/PersonalMonorepo/mac-setup/dotfiles --target /Users/$USER```

you can set stow to automatically use these dotfiles as the source, and your user folder as the destination. Here follows a brief description of the dotfiles that can be used:

1. [zsh](https://en.wikipedia.org/wiki/Z_shell) - The shell we use. This has some [oh-my-zsh](https://ohmyz.sh/), as well as aliases. It should be noted that there is also .zshenv, which is not committed as it contains sensitive data.
2. [stow](https://www.gnu.org/software/stow/) - See above. There is no other configuration stored here
3. [vim](https://en.wikipedia.org/wiki/Vim_(text_editor)) - Just a few small config changes. Maybe we should dig into that a bit.