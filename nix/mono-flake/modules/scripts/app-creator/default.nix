{ inputs, globals, pkgs, machine-config, lib, ...}:
{
 imports = [
    ./app-creator-add-ingress.nix
 ];
}
