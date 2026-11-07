{ config, pkgs, lib, ... }:

let
  extraGnomeExtensionsList = with pkgs.gnomeExtensions; [
    display-configuration-switcher
  ];

in {
  imports = [
    ../../profiles/home/pomu-workstation.nix
  ];

  home.packages = with pkgs; [
    prismlauncher
    wine64
    pkgsRocm.blender
  ] ++ extraGnomeExtensionsList;

  dconf.settings."org/gnome/shell".enabled-extensions =
    lib.mkAfter (map (ext: ext.extensionUuid) extraGnomeExtensionsList);
}
