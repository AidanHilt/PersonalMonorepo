let
  lib = import <nixpkgs/lib>;

  libFiles = builtins.attrNames (
    lib.filterAttrs (name: type:
      type == "regular" && lib.hasSuffix ".nix" name
    ) (builtins.readDir ./lib)
  );

  loadLib = file: import ./lib/${file} { inherit lib; };

in
builtins.foldl' (acc: file:
  acc // (loadLib file)
) {} libFiles