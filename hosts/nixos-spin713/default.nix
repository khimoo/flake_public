# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running 'nixos-help').

{ config, pkgs, ... }: {
  imports = [ # Include the results of the hardware scan.
    ./hardware.nix
    ./nix-sd-card.nix
    ./sleep.nix
    ./chrome-audio.nix
    ../../modules/nixos/common.nix
  ];

  local.gnome.transparentFullscreen.enable = true;

  # スワップパーティションは eMMC 上にあり読み戻しが遅いので、優先度の高い zram を先に使う。
  # パーティションは hibernate のイメージを書き込む場所（sleep.nix）なので残す。
  zramSwap.enable = true;

  # Mesa は Intel の VA-API ドライバを含まないので、入れないと動画のデコードが CPU で行われる。
  hardware.graphics.extraPackages = [ pkgs.intel-media-driver ];

  # GNOME の画面の自動回転に要る。NixOS の GNOME モジュールは有効にしない。
  hardware.sensor.iio.enable = true;

  local.audio.echoCancel = {
    enable = true;
    source = "alsa_input.platform-avs_dmic.19.auto.stereo-fallback";
  };

  # ビルドはデスクトップに回す。このマシンは 4 スレッドで、/nix も SD カード上にある。
  # デスクトップに繋がらないときに黙って手元でビルドさせず、失敗させて人が判断する。
  local.remoteBuilders = {
    enable = true;
    localBuilds = false;
  };

  local.agentInstructions = builtins.readFile ./agent-instructions.md;
}
