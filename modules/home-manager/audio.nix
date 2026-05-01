# オーディオ制作環境（Home Manager）
# DAW、プラグイン、オーディオツール

{ settings, config, pkgs, lib, ... }:

lib.mkIf settings.features.audio {
  home.packages = with pkgs; [
    # DAW
    bitwig-studio
    zrythm

    # オーディオユーティリティ
    qpwgraph # PipeWire パッチベイ（JACK互換のグラフィカルな接続ツール）
    helvum # もう一つのPipeWireパッチベイ（シンプル版）
    pavucontrol # PulseAudio/PipeWire ボリュームコントロール
  ];
}
