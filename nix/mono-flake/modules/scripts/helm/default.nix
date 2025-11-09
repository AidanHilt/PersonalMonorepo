{ inputs, globals, pkgs, machine-config, lib, ...}:
{
 imports = [
    ./helm-new-application.nix
    ./helm-new-k8s-resource.nix
 ];
}
