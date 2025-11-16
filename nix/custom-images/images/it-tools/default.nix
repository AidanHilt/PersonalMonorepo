{ pkgs, tag }:

let
  it-tools = pkgs.fetchFromGithub {
    owner = "Corentin Thomasset";
    repo = "it-tools";
    rev = "main";
    ref = "";
  };
in

{
  # Return the config for dockerTools.buildImage
  # name and tag are set automatically by the flake

  copyToRoot = pkgs.buildEnv {
    name = "image-root";
    paths = [ pkgs.bash pkgs.curl ];
  };

  config = {
    Cmd = [ "${pkgs.bash}/bin/bash" ];
    WorkingDir = "/app";
    Env = [ "VERSION=${tag}" ];
  };
}