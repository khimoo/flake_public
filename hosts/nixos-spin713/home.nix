{ config, pkgs, lib, ... }:

{
  imports = [ ../../profiles/home/pomu-workstation.nix ];
  local.cargoRemoteRun = {
    enable = true;
    host = "desktop-ts";
  };
  dconf = {
    enable = true;
    settings = {
      "org/gnome/desktop/interface" = {
        text-scaling-factor = 1.25;
      };
    };
  };
}
