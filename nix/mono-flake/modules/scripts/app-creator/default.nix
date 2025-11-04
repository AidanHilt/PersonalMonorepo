{ inputs, globals, pkgs, machine-config, lib, ...}:
{
 imports = [
    ./app-creator-add-terraform-secret.nix
    ./app-creator-create-app.nix
    ./app-creator-add-secret.nix
    ./app-creator-add-ingress.nix
 ];
}
