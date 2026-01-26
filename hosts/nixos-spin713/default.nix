# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running 'nixos-help').

{ config, pkgs, specialArgs, ... }: {
  imports = [ # Include the results of the hardware scan.
    ./hardware.nix
    ./chrome-audio.nix
    ../../modules/nixos/common.nix
  ];

  # /nix/配下をSDカードにしてる場合の設定
  systemd.services."home-manager-${(builtins.head specialArgs.settings.users).username}" = {
    after = [ "nix.mount" "nix-daemon.service" ];
    requires = [ "nix.mount" ];
  };
  programs.niri.enable = true;
}
