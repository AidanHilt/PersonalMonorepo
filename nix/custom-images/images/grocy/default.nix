{ inputs, pkgs, tag, ... }:
let
  # rootfs = pkgs.runCommand "rootfs" {} ''
  #   mkdir -p $out/etc/nginx/conf.d
  # '';

  nixos = inputs.nixpkgs.lib.nixosSystem {
    system = pkgs.system;
    modules = [
      ({ pkgs, ... }: {
        # Minimal container config
        boot.isContainer = true;
        networking.useDHCP = false;
        documentation.enable = false; 
        
        services.grocy.enable = true;
        services.nginx.enable = true;

        system.stateVersion = "24.11";
      })
    ];
  };
in
{
  contents = [nixos];
}