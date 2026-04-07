{ pkgs, tag, ... }:
let

apk = import ../../lib/apk.nix { inherit pkgs tag; };

apkLayer = apk.mkAlpineLayer {
  packages = [
    { name = "curl"; version = "8.17.0-r1"; sha256 = "sha256-i+7WEEZ34TXa1bjg+aIZFvV7oSEbnTrwmi3YKGrPJJg="; }
  ];
};

in
{
  contents = with pkgs; [
    apkLayer
    dash
    uutils-coreutils-noprefix
  ];
}