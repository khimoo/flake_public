# 通話用のエコーキャンセル

{ config, lib, ... }:

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

    services.pipewire = {
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
  };
}
