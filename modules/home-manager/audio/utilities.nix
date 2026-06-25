# オーディオユーティリティ（パッチベイ・ミキサー）

{ settings, pkgs, lib, ... }:

lib.mkIf settings.features.audio {
  home.packages = with pkgs; [
    qpwgraph    # PipeWire パッチベイ（JACK 互換のグラフィカルな接続ツール）
    helvum      # シンプル版 PipeWire パッチベイ
    pavucontrol # PulseAudio/PipeWire ボリュームコントロール
  ];
}
