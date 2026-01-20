{ inputs, globals, pkgs, machine-config, lib, ...}:

let

  unstablePkgs = import inputs.nixpkgs-unstable {system = pkgs.system;};

in

{
  imports = [];

  # TODO Parsec works, but it's kind of ugly. See if we can add a pretty application too
  environment.systemPackages = lib.mkIf (pkgs.system == "x86_64-linux") (with pkgs; [
    discord
    sunshine
    lutris
    gogdl
    heroic
    linuxKernel.packages.linux_zen.xone
    # itch
  ]);

  hardware.xone.enable = true;

  programs.steam = lib.mkIf (pkgs.system == "x86_64-linux") {
    enable = true;
  };

  services.sunshine = {
    enable = true;
    autoStart = true;
    capSysAdmin = true;
    openFirewall = true;
  };
}