{ inputs, globals, pkgs, lib, machine-config, ...}:

let
  workMachine = machine-config.configSwitches.workMachine or false;

  additionalExtensions = if workMachine then with pkgs.nur.repos.rycee.firefox-addons; [
    keeper-password-manager
  ]
  else with pkgs.nur.repos.rycee.firefox-addons; [
    facebook-container
    keepassxc-browser
    sponsorblock
  ];
in

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
        privacy-badger
        refined-github
        ublock-origin
        view-image
      ] ++ additionalExtensions;


      extraConfig = ''
        user_pref("extensions.autoDisableScopes", 0);
        user_pref("extensions.enabledScopes", 15);
        user_pref("browser.startup.page", 3);
        user_pref("browser.aboutConfig.showWarning", false)
        user_pref("browser.fixup.domainwhitelist.lan", true)
      '';
    };
  };
}