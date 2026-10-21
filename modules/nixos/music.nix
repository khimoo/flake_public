# 音楽制作に使う OS の設定（リアルタイム音声、JACK、低レイテンシ）と、ユーザーの音楽アプリ
# （Home Manager の features.audio）を一つの選択で切り替える。通話用のエコーキャンセルは audio.nix。
{ config, lib, settings, ... }:
let
  cfg = config.local.music;
  homeUsers = map (u: u.username) (builtins.filter
    (u: (u.manageHome or true) && builtins.elem u.username cfg.users) settings.users);
in
{
  options.local.music = {
    enable = lib.mkEnableOption "music production";
    users = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ settings.primaryUser ];
      description = "Users who join the audio group and, if Home Manager manages them, get the music applications.";
    };
  };

  config = lib.mkIf cfg.enable {
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
    users.users = lib.genAttrs cfg.users (_: { extraGroups = [ "audio" ]; });
    home-manager.users = lib.genAttrs homeUsers (_: {
      local.profile.features.audio = true;
    });
  };
}
