{ skk-dict, claude-desktop-debian, settings, config, pkgs, lib, ... }:

{
  imports = [
    ../../modules/home-manager/core.nix
    ../../modules/home-manager/gui.nix
    ../../modules/home-manager/dev.nix
    ../../modules/home-manager/desktop-entry.nix
  ];

  home.packages = [
    claude-desktop-debian.packages.${pkgs.system}.claude-desktop-fhs
  ];

  dconf = {
    enable = true;
    settings = {
      "org/gnome/desktop/interface" = {
        text-scaling-factor = 1.25;
      };
    };
  };
}
