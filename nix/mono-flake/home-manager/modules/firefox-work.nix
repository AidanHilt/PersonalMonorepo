{ inputs, globals, pkgs, lib, ...}:

{
  home.activation.firefoxProfile = lib.hm.dag.entryAfter [ "writeBoundry" ] ''
    run mv $HOME/Library/Application\ Support/Firefox/profiles.ini $HOME/Library/Application\ Support/Firefox/profiles.hm
    run cp $HOME/Library/Application\ Support/Firefox/profiles.hm $HOME/Library/Application\ Support/Firefox/profiles.ini
    run rm -f $HOME/Library/Application\ Support/Firefox/profiles.ini.bak
    run chmod u+w $HOME/Library/Application\ Support/Firefox/profiles.ini
  '';

  programs.firefox = {
    enable = true;
    package = null;
    profiles.aidan = {
      isDefault = true;
      extensions = with pkgs.nur.repos.rycee.firefox-addons; [
        clearurls
        docsafterdark
        don-t-fuck-with-paste
        privacy-badger
        refined-github
        ublock-origin
        view-image
        keeper-password-manager
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