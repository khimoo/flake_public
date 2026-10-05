{ config, pkgs, lib, ... }:

let
  gnomeExtensionsList = with pkgs.gnomeExtensions; [
    clipboard-history
    extension-list
    kimpanel
    gsconnect
    paperwm
    (pkgs.callPackage ../../../packages/mic-indicator-visibility-manager { })
  ];

in lib.mkIf config.local.profile.features.gnome {
  home.packages = gnomeExtensionsList;

  dconf = {
    enable = true;
    settings = {
      "org/gnome/shell" = {
        disable-user-extensions = false;
        enabled-extensions = map (ext: ext.extensionUuid) gnomeExtensionsList;
      };
      "org/gnome/shell/extensions/mic-indicator-visibility" = {
        show-virtual-sources = true;
        ignored-properties = [
          "node.name:echo-cancel-capture"
          "node.name:echo-cancel-reference"
        ];
      };
      "org/gnome/desktop/interface" = {
        accent-color = "blue";
        color-scheme = "prefer-dark";
        show-battery-percentage = true;
        toolkit-accessibility = false;
      };
    };
  };

  systemd.user.sessionVariables.NIXOS_OZONE_WL = "1";
}
