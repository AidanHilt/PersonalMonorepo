{ inputs, globals, pkgs, machine-config, lib, ...}:

{
  programs.keepassxc = {
    enable = true;
    package = null;

    settings = {
      Browser.Enabled = true;
    };
  };

  home.file."org.keepassxc.keepassxc_browser.json" = {
    target = ".mozilla/native-messaging-hosts/org.keepassxc.keepassxc_browser.json";
    text = ''
      {
        "allowed_extensions": [
          "keepassxc-browser@keepassxc.org"
        ],  
        "description": "KeePassXC integration with native messaging support",
        "name": "org.keepassxc.keepassxc_browser",
        "path": "${pkgs.keepassxc}/bin/keepassxc-proxy",
        "type": "stdio"
      }
    '';
  };

}