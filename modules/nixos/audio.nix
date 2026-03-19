# オーディオ制作環境設定
# Musnixを使用したリアルタイムオーディオ設定

{ config, lib, pkgs, ... }:

{
  # Musnix有効化
  musnix = {
    enable = true;
    kernel.realtime = false;

    # rtkit（既に有効化されているが、musnixでも明示的に設定）
    rtirq.enable = true;

    # DAスケジューラの最適化
    das_watchdog.enable = true;
  };

  # PipeWireのJACK対応を追加（既存のPipeWire設定に追加）
  services.pipewire = {
    jack.enable = true;

    # 低レイテンシー設定
    extraConfig.pipewire."92-low-latency" = {
      "context.properties" = {
        "default.clock.rate" = 48000;
        "default.clock.quantum" = 128;
        "default.clock.min-quantum" = 32;
        "default.clock.max-quantum" = 2048;
      };
    };
  };

  # プラグインパスはmusnixが自動的に設定するため、ここでは不要
}
