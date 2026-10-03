# オーディオ制作環境設定
# Musnixを使用したリアルタイムオーディオ設定

{ config, lib, pkgs, ... }:

let
  cfg = config.local.audio.echoCancel;
in
{
  options.local.audio.echoCancel = {
    enable = lib.mkEnableOption "a WebRTC echo-canceled microphone";
    source = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = "PipeWire node.name of the physical microphone to capture.";
    };
  };

  config = {
    assertions = lib.optional cfg.enable {
      assertion = config.services.pipewire.enable && cfg.source != "";
      message = "local.audio.echoCancel requires PipeWire and a physical microphone source.";
    };

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

      # 実マイクを固定して自己参照を避け、既定の出力をエコーの参照音にする。
      # docs/architecture/audio-echo-cancel.md
      extraConfig.pipewire."93-echo-cancel" = lib.mkIf cfg.enable {
        "context.modules" = [
          {
            name = "libpipewire-module-echo-cancel";
            args = {
              "library.name" = "aec/libspa-aec-webrtc";
              "monitor.mode" = true;
              "audio.rate" = 48000;
              "aec.args" = {
                "webrtc.gain_control" = false;
                "webrtc.noise_suppression" = false;
              };
              "capture.props" = {
                "node.name" = "echo-cancel-capture";
                "target.object" = cfg.source;
                "node.dont-fallback" = true;
                "node.linger" = true;
              };
              "source.props" = {
                "node.name" = "echo-cancel-source";
                "node.description" = "Echo-Cancel Microphone";
                "priority.session" = 0;
              };
              "sink.props"."node.name" = "echo-cancel-reference";
            };
          }
        ];
      };
    };

    # プラグインパスはmusnixが自動的に設定するため、ここでは不要
  };
}
