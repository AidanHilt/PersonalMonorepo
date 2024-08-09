{ config, pkgs, ... }:
let
  vim-config = builtins.fetchGit {
    url = "https://github.com/AidanHilt/PersonalMonorepo.git";
    ref = "feat/nixos";
    rev = "25a69ca0818b9abd82175a1f7a918225745c6898";
  } + "/nix/modules/vim.nix";
  rke2-secondary = builtins.fetchGit {
    url = "https://github.com/AidanHilt/PersonalMonorepo.git";
    ref = "feat/nixos";
    rev = "293a01e5452cba199554fa321418f6d61dd52884";
  } + "/nix/modules/rke-secondary.nix";
in
{
  imports =
    [ # Include the results of the hardware scan.
      ./hardware-configuration.nix
      vim-config
      rke2-secondary
    ];

  users.defaultUserShell = pkgs.zsh;
  environment.pathsToLink = [ "/share/zsh" ];

  #=======================================
  # Bootloader
  #=======================================
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  networking.hostName = "nixos"; # Define your hostname.

  #=======================================
  # Enable networking
  #=======================================
  networking.networkmanager.enable = true;

  #=======================================
  # Set time zone.
  #=======================================
  time.timeZone = "America/New_York";

  #=======================================
  # Select internationalisation properties.
  #=======================================
  i18n.defaultLocale = "en_US.UTF-8";

  i18n.extraLocaleSettings = {
    LC_ADDRESS = "en_US.UTF-8";
    LC_IDENTIFICATION = "en_US.UTF-8";
    LC_MEASUREMENT = "en_US.UTF-8";
    LC_MONETARY = "en_US.UTF-8";
    LC_NAME = "en_US.UTF-8";
    LC_NUMERIC = "en_US.UTF-8";
    LC_PAPER = "en_US.UTF-8";
    LC_TELEPHONE = "en_US.UTF-8";
    LC_TIME = "en_US.UTF-8";
  };

  #=======================================
  # Configure keymap in X11
  #=======================================
  services.xserver = {
    layout = "us";
    xkbVariant = "";
  };

  #=====================================================================
  # Define a user account. Don't forget to set a password with ‘passwd’.
  #=====================================================================
  users.users.aidan = {
    isNormalUser = true;
    description = "Aidan";
    extraGroups = [ "networkmanager" "wheel" ];
  };

  #=======================================
  # Allow unfree packages
  #=======================================
  nixpkgs.config.allowUnfree = true;

  #============================================
  # List packages installed in system profile.
  #============================================
  environment.systemPackages = with pkgs; [
    vim
    git
    yq
    jq
    zsh
    pkgs.adguardhome
    pkgs.rke2
];

  # Enable the OpenSSH daemon.
  services.openssh.enable = true;

  services.adguardhome.enable = true;

  services.rke-secondary = {
    serverAddr = "https://192.168.86.192:6443";
    tokenFile = "/var/lib/rancher/rke2/server/node-token";
  };

  networking.firewall.allowedTCPPorts = [ 53 3000 6443 ];
  networking.firewall.allowedUDPPorts = [ 53 ];

  system.stateVersion = "24.11";

  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  programs.zsh.enable = true;
}
