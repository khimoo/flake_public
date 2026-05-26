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
  systemd.services."home-manager-${specialArgs.settings.primaryUser}" = {
    after = [ "nix.mount" "nix-daemon.service" ];
    requires = [ "nix.mount" ];
  };
  programs.niri.enable = true;

  # リモートビルダ (nixos-desktop) へ初回 SSH 接続したときに
  # ホスト鍵を自動で known_hosts に追加する。
  # `sudo nixos-rebuild --build-host pomu@nixos-desktop.local` は root として
  # SSH 接続するため、root の known_hosts に未登録だと接続が止まる
  programs.ssh.extraConfig = ''
    Host nixos-desktop nixos-desktop.local
      StrictHostKeyChecking accept-new
  '';
}
