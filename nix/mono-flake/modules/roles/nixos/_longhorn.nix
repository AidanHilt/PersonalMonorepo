{ inputs, globals, pkgs, machine-config, ...}:

{
  environment.systemPackages = with pkgs; [
    openiscsi
  ];

  services.openiscsi = {
    enable = true;
    name = hostname;
  };
}