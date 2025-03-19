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

  bootstrapVbox = pkgs.writeShellScriptBin "bootstrap-vbox" ''
    PARTITION_CHECK=$(lsblk -nd -o PTTYPE "/dev/sda" 2> /dev/null)
    if [ -z "$PARTITION_CHECK" ]; then
      echo "Performing VirtualBox disk partitioning..."
      echo "WARNING: All data on /dev/sda will be lost!"
      read -p "Continue? (y/n): " confirm
      
      if [ "$confirm" != "y" ]; then
          echo "Operation cancelled"
          exit 0
      fi
      echo "Partitioning disk"
      parted /dev/sda -- mklabel gpt
      parted /dev/sda -- mkpart root ext4 512MB 100%
      parted /dev/sda -- mkpart ESP fat32 1MB 512MB
      parted /dev/sda -- set 2 esp on

      mkfs.ext4 -L ROOTDIR /dev/sda1
      mkfs.fat -F 32 -n BOOT /dev/sda2

      mount /dev/disk/by-label/ROOTDIR /mnt
      mkdir -p /mnt/boot
      mount /dev/disk/by-label/BOOT /mnt/boot
    else
      echo "Disk already looks partitioned. If it's not, reset it"
    fi

    echo "Select hostname for flake install:"
    echo "1) staging-cluster-1"
    echo "2) staging-cluster-2"
    echo "3) staging-cluster-3"
    read -p "Enter selection (1-3):" hostname_choice

    case "$hostname_choice" in 
      1)
        hostname="staging-cluster-1"
      ;;
      2)
        hostname="staging-cluster-2"
      ;;
      3)
        hostname="staging-cluster-3"
      ;;
      *)
        echo "Invalid option $hostname_choice"
        exit 1
      ;;
    esac

    nixos-install --flake "github:AidanHilt/PersonalMonorepo/feat/staging-cluster-setup?dir=nix/server-setup#$hostname"
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