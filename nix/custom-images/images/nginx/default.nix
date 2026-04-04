{ pkgs, tag, ... }:
let

apk = import ../lib/apk.nix { inherit pkgs tag; };

apkLayer = apk.mkAlpineLayer {
  packages = [
    { name = "curl";   version = "8.5.0-r0"; sha256 = "sha256-AAAA…"; }
    { name = "libcurl"; version = "8.5.0-r0"; sha256 = "sha256-BBBB…"; }
  ];
};

in
{
  contents = with pkgs; [
    apkLayer
  ];
}