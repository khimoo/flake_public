{ skk-dict, settings, config, pkgs, lib, ... }:

let
  extraGnomeExtensionsList = with pkgs.gnomeExtensions; [
    display-configuration-switcher
  ];

in {
  imports = [
    ../../modules/home-manager/core.nix
    ../../modules/home-manager/gui.nix
    ../../modules/home-manager/dev.nix
    ../../modules/home-manager/desktop-entry.nix
  ];

  home.packages = with pkgs; [
    prismlauncher
    wine64
    steam
    blender-hip
  ] ++ extraGnomeExtensionsList;

  dconf.settings."org/gnome/shell".enabled-extensions =
    lib.mkAfter (map (ext: ext.extensionUuid) extraGnomeExtensionsList);
}
