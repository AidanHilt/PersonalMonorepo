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

# 1. Welcome message
echo "\n📱 Let's finish setting up your Mac!\n"
sleep 1

# 2. Wallpaper settings
if get_confirmation "Would you like to change your wallpaper?"; then
    echo "\nOpening Desktop & Screen Saver preferences..."
    open "x-apple.systempreferences:com.apple.preference.desktopscreeneffect" -W
fi

# 3. Login items setup
echo "\n⚙️ Enable the following apps in login items:"
echo "   • f.lux"
echo "   • Rectangle"
echo "   • Flycut"
echo "\nOpening Login Items preferences..."
open "x-apple.systempreferences:com.apple.preference.security?General" -W

# 4. Firefox launch
echo "\n🦊 We're going to launch Firefox now. It's expected to fail - this is normal and will finalize some issues we have because of the nix+homebrew combo."
sleep 2
open -a "Firefox"
sleep 3

# 5. Reboot prompt
if get_confirmation "\n🔄 Would you like to reboot now?"; then
    echo "\nRebooting in 5 seconds... Press Ctrl+C to cancel."
    sleep 5
    sudo reboot
else
    echo "\n✨ Setup complete! Please remember to reboot your computer soon."
fi
  '';

in
{
  environment.systemPackages = [
    finish-setup
  ];
}