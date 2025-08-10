{ inputs, globals, pkgs, machine-config, lib, ...}:

let
  ATILS_CONFIG_DIRECTORY = "${machine-config.userBase}/${machine-config.username}/.atils";
in

{
  imports = [
    ./_context-create-context.nix
    ./_context-delete-context.nix
    ./_context-list-contexts.nix
    ./_context-populate-context.nix
  ];

  environment.systemPackages = with pkgs; [
    dotenvx
  ];

  environment.variables = {
    ATILS_CONFIG_DIRECTORY = ATILS_CONFIG_DIRECTORY;
    ATILS_CONTEXTS_DIRECTORY = "${ATILS_CONFIG_DIRECTORY}/contexts";
    ATILS_CONTEXTS_CURRENT_CONTEXT_FILE = "${ATILS_CONFIG_DIRECTORY}/contexts/.current-context";
  };
}