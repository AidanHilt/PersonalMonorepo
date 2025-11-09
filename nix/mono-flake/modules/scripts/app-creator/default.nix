{ inputs, globals, pkgs, machine-config, lib, ...}:
{
 imports = [
    ./app-creator-add-argocd-app.nix
    ./app-creator-add-postgres-config.nix
    ./app-creator-add-terraform-secret.nix
    ./app-creator-add-argocd-app.nix
    ./app-creator-add-secret.nix
    ./app-creator-add-ingress.nix
 ];
}
