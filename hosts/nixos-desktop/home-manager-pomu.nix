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

  # スリープ前に active だった display-configuration-switcher 設定を復帰時に再適用する
  programs.gnomeDisplayDefault.enable = true;
}
