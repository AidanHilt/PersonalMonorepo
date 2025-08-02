{ inputs, globals, pkgs, machine-config, lib, ...}:

{
  imports = [
    ./_context-create-context.nix
    ./_context-delete-context.nix
    ./_context-list-contexts.nix
  ];

  environment.systemPackages = with pkgs; [
    dotenvx
  ];

  environment.variables = {
    ATILS_CONFIG_DIRECTORY = "${machine-config.userBase}/${machine-config.username}/.atils";
  };
}