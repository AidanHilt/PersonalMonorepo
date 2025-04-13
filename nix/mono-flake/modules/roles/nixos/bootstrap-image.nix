{ inputs, globals, pkgs, ...}:

let
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

    BRANCH="master"

    echo "Enter branch to build config from (default is master):"
    read -p "Enter branch name: " BRANCH

    nixos-install --flake "github:AidanHilt/PersonalMonorepo/$BRANCH?dir=nix/server-setup#$hostname"
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
    bootstrapVbox
  ];

  system.stateVersion = "24.11";
}