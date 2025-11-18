{ pkgs, tag }:
let
  it-tools = pkgs.it-tools.overrideAttrs ( oldAttrs: {
    buildPhase = ''
      runHook preBuild
      export BASE_URL=/it-tools

      pnpm build

      runHook postBuild
    '';
  });
in
{
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