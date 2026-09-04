{ pkgs, tag }:
let

in

{
  name = "transmission";
  inherit tag;

  copyToRoot = pkgs.buildEnv {
    name = "image-root";
    paths = with pkgs; [ fakeNss transmission_4 ];
  };

  config = {
    Cmd = [ "${pkgs.transmission}/bin/transmission" ];
    ExposedPorts = {
      "9091/tcp" = {};
    };
    WorkingDir = "/";
  };
}