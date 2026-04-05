{ skk-dict, claude-desktop-debian, settings, config, pkgs, lib, ... }:

{
  imports = [
    ../../modules/home-manager/core.nix
    ../../modules/home-manager/gui.nix
    ../../modules/home-manager/dev.nix
    ../../modules/home-manager/desktop-entry.nix
    ../../modules/home-manager/claude-desktop.nix
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
