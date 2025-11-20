# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running 'nixos-help').

{ config, pkgs, specialArgs, ... }: {
  imports = [ # Include the results of the hardware scan.
    ./hardware-configuration.nix
    ./chrome-device.nix
    ../common-hosts/default.nix
  ];

  # /nix/配下をSDカードにしてる場合の設定
  systemd.services."home-manager-${specialArgs.settings.username}" = {
    after = [ "nix.mount" "nix-daemon.service" ];
    requires = [ "nix.mount" ];
  };
  programs.niri.enable = true;
  environment.sessionVariables.NIXOS_OZONE_WL = "1";
}
