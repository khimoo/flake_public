{ skk-dict, settings, config, pkgs, lib, ... }:

let
  extraGnomeExtensionsList = with pkgs.gnomeExtensions; [
    display-configuration-switcher
  ];

in {
  home.packages = with pkgs; [
    prismlauncher
    wine64
    steam
    blender-hip
  ] ++ extraGnomeExtensionsList;

  dconf.settings."org/gnome/shell".enabled-extensions =
    lib.mkAfter (map (ext: ext.extensionUuid) extraGnomeExtensionsList);
}
