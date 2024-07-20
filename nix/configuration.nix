# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).

{ config, pkgs, ... }:

{
  imports =
    [ # Include the results of the hardware scan.
      ./hardware-configuration.nix
     (fetchTarball {
      url="https://github.com/nix-community/nixos-vscode-server/tarball/master";
      sha256="1rq8mrlmbzpcbv9ys0x88alw30ks70jlmvnfr2j8v830yy5wvw7h";
     })
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
  # Vim setup and config
  #=======================================
  environment.variables = { EDITOR = "vim"; };

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
  services.vscode-server.enable = true;

  services.adguardhome.enable = true;

  services.rke2.enable = true;


  networking.firewall.allowedTCPPorts = [ 53 3000 6443 ];
  networking.firewall.allowedUDPPorts = [ 53 ];

  system.stateVersion = "24.05";

  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  programs.zsh.enable = true;
}
