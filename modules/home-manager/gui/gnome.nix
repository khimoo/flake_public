{ settings, config, pkgs, lib, ... }:

let
  gnomeExtensionsList = with pkgs.gnomeExtensions; [
    clipboard-history
    extension-list
    kimpanel
    gsconnect
    paperwm
  ];

in lib.mkIf settings.features.gnome {
  home.packages = gnomeExtensionsList;

  dconf = {
    enable = true;
    settings = {
      "org/gnome/shell" = {
        disable-user-extensions = false;
        enabled-extensions = map (ext: ext.extensionUuid) gnomeExtensionsList;
      };
      "org/gnome/desktop/interface" = {
        accent-color = "blue";
        color-scheme = "prefer-dark";
        show-battery-percentage = true;
        toolkit-accessibility = false;
      };
    };
  };

}
