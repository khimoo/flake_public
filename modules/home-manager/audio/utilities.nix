# オーディオユーティリティ（パッチベイ・ミキサー）

{ config, pkgs, lib, ... }:

lib.mkIf config.local.profile.features.audio {
  home.packages = with pkgs; [
    qpwgraph    # PipeWire パッチベイ（JACK 互換のグラフィカルな接続ツール）
    pavucontrol # PulseAudio/PipeWire ボリュームコントロール
  ];
}
