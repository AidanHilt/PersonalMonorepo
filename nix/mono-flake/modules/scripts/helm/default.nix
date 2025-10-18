{ inputs, globals, pkgs, machine-config, lib, ...}:
{
 imports = [
    ./helm-new-k8s-resource.nix
 ];
}
