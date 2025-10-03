{ inputs, globals, pkgs, machine-config, lib, ...}:

{
  imports = [
    ./_docker.nix
    ./_guided-setup.nix

    ../universal/universal-base.nix
  ];

  environment.systemPackages = with pkgs; [
    defaultbrowser
  ];

  system.stateVersion = 5;

  programs.zsh.enable = true;

  security.pam.services.sudo_local.touchIdAuth = true;

  system.primaryUser = "${machine-config.username}";

  users.knownUsers = ["${machine-config.username}"];

  users.users."${machine-config.username}".uid = 501;

  system.defaults = {
    dock = {
      expose-group-apps = true;
      show-recents = false;
    };

    finder = {
      AppleShowAllExtensions = true;
      AppleShowAllFiles = true;
      FXEnableExtensionChangeWarning = false;
      ShowPathbar = true;
      ShowStatusBar = true;
      FXPreferredViewStyle = "icnv";
    };

    NSGlobalDomain = {
      "com.apple.swipescrolldirection" = false;
    };

    screencapture = {
      location = "/Users/${machine-config.username}/Desktop/screenshots";
      show-thumbnail = false;
    };

    trackpad = {
      Clicking = true;
      TrackpadRightClick = true;
      #TrackpadThreeFingerDrag = true;
    };

    CustomSystemPreferences = {
      "com.apple.AppleMultitouchTrackpad" = {
        TrackpadThreeFingerDrag = 0;
      };
    };
  };

  launchd.user.agents.fix-trackpad = {
    serviceConfig = {
      ProgramArguments = [
        "${pkgs.bash}/bin/bash"
        "-c"
        ''
          /usr/bin/defaults write com.apple.AppleMultitouchTrackpad TrackpadThreeFingerDrag -bool true
          /usr/bin/defaults write com.apple.driver.AppleBluetoothMultitouch.trackpad TrackpadThreeFingerDrag -bool true

          # Set for external/Bluetooth trackpad
          /usr/bin/defaults write com.apple.AppleMultitouchTrackpad Dragging -bool false
          /usr/bin/defaults write com.apple.driver.AppleBluetoothMultitouch.trackpad Dragging -bool false

          # Sometimes it's in accessibility settings
          /usr/bin/defaults write com.apple.AppleMultitouchTrackpad DragLock -bool false
          /usr/bin/defaults write com.apple.driver.AppleBluetoothMultitouch.trackpad DragLock -bool false
          /usr/bin/killall Dock
        ''
      ];
      RunAtLoad = true;
      StandardErrorPath = "/tmp/trackpad-fix.err";
      StandardOutPath = "/tmp/trackpad-fix.out";
    };
  };

  environment.systemPath = [
    "/opt/homebrew/bin"
  ];

  homebrew = {
    enable = true;

    onActivation = {
      cleanup = "uninstall";
      upgrade = true;
    };

    casks = [
      "firefox"
      "google-chrome"
      "flux"
      "rectangle"
      "flycut"
      "iterm2"
      "visual-studio-code"
    ];
  };
}
