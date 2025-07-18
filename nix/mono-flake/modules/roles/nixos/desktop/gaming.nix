{ inputs, globals, pkgs, machine-config, ...}:

{
  imports = [];

  # TODO Parsec works, but it's kind of ugly. See if we can add a pretty application too
  environment.systemPackages = with pkgs; [
    discord
  ];

  programs.steam = {
    enable = true;
  };

  services.sunshine = {
    enable = true;
    openFirewall = true;
  };
}