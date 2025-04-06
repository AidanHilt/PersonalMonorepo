{ inputs, globals, machine-config, pkgs, lib, ...}:

{
  home.activation.firefoxProfile = lib.mkIf (pkgs.system == "aarch64-darwin")
    (lib.hm.dag.entryAfter [ "writeBoundry" ] ''
      run mv $HOME/Library/Application\ Support/Firefox/profiles.ini $HOME/Library/Application\ Support/Firefox/profiles.hm
      run cp $HOME/Library/Application\ Support/Firefox/profiles.hm $HOME/Library/Application\ Support/Firefox/profiles.ini
      run rm -f $HOME/Library/Application\ Support/Firefox/profiles.ini.bak
      run chmod u+w $HOME/Library/Application\ Support/Firefox/profiles.ini
  '');

  programs.firefox = {
    enable = true;
    package = lib.mkIf (pkgs.system == "aarch64-darwin") null;
    profiles.aidan = {
      isDefault = true;
      extensions.packages = with pkgs.nur.repos.rycee.firefox-addons; [
        clearurls
        docsafterdark
        don-t-fuck-with-paste
        facebook-container
        keepassxc-browser
        privacy-badger
        refined-github
        sponsorblock
        ublock-origin
        view-image
      ];


      extraConfig = ''
        user_pref("extensions.autoDisableScopes", 0);
        user_pref("extensions.enabledScopes", 15);
        user_pref("browser.startup.page", 3);
        user_pref("browser.aboutConfig.showWarning", false)
      '';

    };
  };
}