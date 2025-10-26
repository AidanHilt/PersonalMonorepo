{ inputs, globals, pkgs, machine-config, lib, ...}:
{
 imports = [
    ./app-creator-add-secret.nix
    ./app-creator-add-ingress.nix
 ];
}
