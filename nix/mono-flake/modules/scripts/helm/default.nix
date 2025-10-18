{ inputs, globals, pkgs, machine-config, lib, ...}:
{
 imports = [
    ./helm-k8s-resource-new-stack.nix
    ./helm-new-k8s-resource.nix
 ];
}
