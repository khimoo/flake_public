{ config, pkgs, lib, ... }:

{
  imports = [ ../../profiles/home/pomu-workstation.nix ];
  dconf = {
    enable = true;
    settings = {
      "org/gnome/desktop/interface" = {
        text-scaling-factor = 1.25;
      };
    };
  };
}
