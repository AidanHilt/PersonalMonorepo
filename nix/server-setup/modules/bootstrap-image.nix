{ inputs, globals, pkgs, ...}:

let

  installFlake = pkgs.writeShellScriptBin "install-flake" ''
    BRANCH="master"
    while [[ $# -gt 0 ]]; do
      case $1 in
        --branch)
          BRANCH="$2"
          shift 2
          ;;
        *)
          echo "Unknown option: $1"
          exit 1
          ;;
      esac
    done

    printf "Please enter a hostname: "
    read hostname

    if [ -z "$hostname" ]; then
      printf "Error: Hostname is required.\n" >&2
      exit 1
    fi

    sudo nixos-rebuild switch --flake "github:AidanHilt/PersonalMonorepo/$BRANCH?dir=nix/server-setup#$hostname"
  '';

  bootstrapCommand = pkgs.writeShellScriptBin "bootstrap" ''
  # Script to handle platform-specific disk operations

  # Function to display error messages and exit
  error_exit() {
      echo "Error: $1" >&2
      exit 1
  }

  # Function to check if command executed successfully
  check_command() {
      if [ $? -ne 0 ]; then
          error_exit "$1"
      fi
  }

  # Function to check if running as root
  check_root() {
      if [ "$(id -u)" -ne 0 ]; then
          error_exit "This script must be run as root"
      fi
  }

  # Check root privileges
  check_root

  # Display platform selection menu
  echo "Select platform:"
  echo "1) vbox"
  read -p "Enter selection (1): " platform_choice

  # Set default if empty
  if [ -z "$platform_choice" ]; then
      platform_choice="1"
  fi

  # Convert number selection to platform name
  case "$platform_choice" in
      1)
          platform="vbox"
          ;;
      *)
          error_exit "Invalid platform selection"
          ;;
  esac

  echo "Selected platform: $platform"

  # Perform platform-specific actions
  case "$platform" in
      vbox)
          echo "Performing VirtualBox disk partitioning..."
          echo "This will create a single partition on /dev/sda"
          echo "WARNING: All data on /dev/sda will be lost!"
          read -p "Continue? (y/n): " confirm
          
          if [ "$confirm" != "y" ]; then
              echo "Operation cancelled"
              exit 0
          fi
          
          # Check if parted is available
          command -v parted >/dev/null 2>&1 || error_exit "parted is not installed"
          
          # Create a single partition on /dev/sda
          echo "Creating partition on /dev/sda..."
          parted -s /dev/sda mklabel msdos
          check_command "Failed to create GPT label"
          
          parted -s /dev/sda mkpart primary ext4 0% 100%
          check_command "Failed to create partition"
          
          echo "Setting partition as bootable..."
          parted -s /dev/sda set 1 boot on
          parted -s /dev/sda set 1 bios_grub on
          check_command "Failed to set boot flag"
          
          echo "Partitioning complete. New partition table:"
          parted -s /dev/sda print
          
          echo "Successfully created partition on /dev/sda"

          mkfs.ext4 /dev/sda1 -L ROOTDIR
          ;;
      *)
          error_exit "Platform handling not implemented"
          ;;
  esac

  exit 0
  '';

in

{
  users.groups.aidan = {};

  services.openssh = {
    enable = true;

    hostKeys = [
      {
        path = "/etc/ssh/ssh_host_ed25519_key";
        type = "ed25519";
      }
    ];
  };

  users.users.aidan = {
    home = "/home/aidan";
    group = "aidan";
    extraGroups = [ "networkmanager" "wheel" ];
    isNormalUser = true;

    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIImw5CsGmsR1WTunv5bvNcozmoUSgJf76RMvy6SZtA2R aidan@hyperion"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEEAi2UjaWUsDVY6wUMMcIjDXzyizhax86Z0J2I6fYM0 nixos@nixos"
    ];
  };

  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  environment.systemPackages = [
    pkgs.git
    pkgs.vim
    pkgs.eza
    pkgs.htop
    installFlake
  ];

  system.stateVersion = "24.11";
}