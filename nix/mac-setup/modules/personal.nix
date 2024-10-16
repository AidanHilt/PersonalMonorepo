{ inputs, config, pkgs, ... }:

let
  p2n = (inputs.poetry2nix.lib.mkPoetry2Nix { inherit pkgs; });

  pypkgs-build-requirements = {
    argparse = ["setuptools"];
    click = ["setuptools"];
    asyncio = ["setuptools"];
    shutils = ["setuptools"];
  };

  p2n-overrides = p2n.defaultPoetryOverrides.extend (self: super:
    builtins.mapAttrs (package: build-requirements:
      (builtins.getAttr package super).overridePythonAttrs (old: {
        buildInputs = (old.buildInputs or [ ]) ++ (builtins.map (pkg: if builtins.isString pkg then builtins.getAttr pkg super else pkg) build-requirements);
      })
    ) pypkgs-build-requirements
  );

  atils = p2n.mkPoetryApplication {
    projectDir = builtins.fetchGit {
      url = "https://github.com/AidanHilt/PersonalMonorepo.git";
      ref = "feat/nix-darwin";
      rev = "6d6f65206bf1adbc99993081861b88525305da68"; #pragma: allowlist secret
    } + "/atils";

    overrides = p2n-overrides;
    preferWheels = true;
  };
in

{
  age.secrets.smb-mount-config = {
    file = ../secrets/smb-mount-config.age;
    path = "/etc/smb_mount";
    symlink = false;
  };

  homebrew = {
    casks = [
      "discord"
      "steam"
      "vlc"
      "parsec"
      "keepassxc"
      "spotify"
      "tor-browser"
      "orbstack"
      "postman"
      "utm"
    ];
  };

  system.defaults = {
    dock = {
      persistent-apps = [
        #iTerm
        "/Applications/iTerm.app"
        #Settings
        "/System/Applications/System Settings.app"
        #Firefox
        "/Applications/Firefox.app"
        #VSCode
        "/Applications/Visual Studio Code.app"
        #Discord
        "/Applications/Discord.app"
        #Parsec
        "/Applications/Parsec.app"
        #Spotify
        "/Applications/Spotify.app"
        #Orbstack
        "/Applications/OrbStack.app"
        #ActivityMonitor
        "/System/Applications/Utilities/Activity Monitor.app"
        #KeePassXC
        "/Applications/KeePassXC.app"
      ];
    };
  };

  environment.systemPackages = [
    inputs.agenix.packages.${pkgs.system}.agenix
    atils
  ];

  environment.etc = {
    auto_master = {
      text = ''
#
# Automounter master map
#
+auto_master    # Use directory service
#/net     -hosts    -nobrowse,hidefromfinder,nosuid
/home     auto_home -nobrowse,hidefromfinder
/Network/Servers  -fstab
/-      -static
/-      smb_mount
      '';
    };
  };
}