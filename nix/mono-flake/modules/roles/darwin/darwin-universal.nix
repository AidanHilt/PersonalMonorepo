{ inputs, globals, pkgs, machine-config, ...}:

{
  programs.zsh.enable = true;

  security.pam.enableSudoTouchIdAuth = true;

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
      TrackpadThreeFingerDrag = true;
    };
  };

  system.activationScripts = {
    postUserActivation = {
      text = "defaultbrowser firefox";
    };
  };

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
