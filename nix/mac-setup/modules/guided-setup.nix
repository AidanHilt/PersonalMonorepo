{ inputs, pkgs, globals, ... }:

let
  finish-setup = pkgs.writeShellScriptBin "finish-setup" ''
# Function to get user confirmation
get_confirmation() {
    local prompt="$1"
    local response

    while true; do
        echo -n "$prompt (y/n): "
        read -r response
        case "$response" in
            [yY]|[yY][eE][sS]) return 0 ;;
            [nN]|[nN][oO]) return 1 ;;
            *) echo "Please enter y/n" ;;
        esac
    done
}

# Welcome message
echo "📱 Let's finish setting up your Mac!"
sleep 1

# Secrets setup
if get_confirmation "Agenix secrets are likely NOT decrypted at this point. Confirm to set them up"; then
  sudo ssh-keygen -A
  curl -F "file=@/etc/ssh/ssh_host_rsa_key.pub" https://x0.at
  echo "This is gonna suck, but you'll need to update the agenix secrets on a machine that's already set up."
  echo "The key that you need to download is at the link above. Make sure the rekeyed files are merged to master for continuing"
  read -p "Press any key to continue: " -n 1 -r
  returnDir=$(pwd)
  cd ~/PersonalMonorepo
  git pull
  cd "$returnDir"
  darwin-rebuild switch --flake ~/PersonalMonorepo/nix/mac-setup
fi

# Rclone sync
if get_confirmation "If you've enabled rsync for a personal machine, select yes to manually sync"; then
  mkdir ~/KeePass
  mkdir ~/Wallpapers
  rclone bisync drive:KeePass ~/KeePass --drive-skip-gdocs --resilient --create-empty-src-dirs --fix-case --slow-hash-sync-only --resync
  rclone bisync drive:Wallpapers ~/Wallpapers --drive-skip-gdocs --resilient --create-empty-src-dirs --fix-case --slow-hash-sync-only --resync
fi


# Wallpaper settings
if get_confirmation "Would you like to change your wallpaper?"; then
    echo "Opening Desktop & Screen Saver preferences..."
    open "x-apple.systempreferences:com.apple.preference.desktopscreeneffect" -W
fi

# Login items setup
echo "⚙️ Enable the following apps in login items:"
echo "   • f.lux"
echo "   • Rectangle"
echo "   • Flycut"
echo "Opening Login Items preferences..."
open "x-apple.systempreferences:com.apple.LoginItems-Settings.extension" -W

# Firefox launch
echo "🦊 We're going to launch Firefox now. It's expected to fail - this is normal and will finalize some issues we have because of the nix+homebrew combo."
sleep 2
open -a "Firefox"
sleep 3

# 5. Reboot prompt
if get_confirmation "🔄 Would you like to reboot now?"; then
    echo "Rebooting in 5 seconds... Press Ctrl+C to cancel."
    sleep 5
    sudo reboot
else
    echo "✨ Setup complete! Please remember to reboot your computer soon."
fi
  '';

in
{
  environment.systemPackages = [
    finish-setup
  ];
}