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

  # ビルドはデスクトップに回す。このマシンは 4 スレッドで、/nix も SD カード上にある。
  # デスクトップに繋がらないときに黙って手元でビルドさせず、失敗させて人が判断する。
  local.remoteBuilders = {
    enable = true;
    localBuilds = false;
  };

  local.agentInstructions = builtins.readFile ./agent-instructions.md;
  local.claudeManagedSettings = "/home/pomu/sagyo/agents-private/claude/managed-settings.json";
}
