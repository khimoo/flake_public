# PrismLauncher のインスタンスをアーカイブして遠隔へ送るコマンド mc-backup を提供する。
#
# PrismLauncher の post-exit フック(Settings -> Custom Commands)から
# `mc-backup "$INST_ID"` として呼ぶ運用を想定している。フック経由なら対象インスタンスは
# 既に終了済みなので、書き込み途中のワールドを掴むことがない。
#
# 使い方:   docs/howtouse/minecraft-backup.md
# 設計判断: docs/architecture/minecraft-backup.md
{ config, pkgs, lib, ... }:

let
  cfg = config.local.minecraftBackup;
in
{
  options.local.minecraftBackup = {
    enable = lib.mkEnableOption "PrismLauncher インスタンスのアーカイブと遠隔送信";

    instancesDir = lib.mkOption {
      type = lib.types.str;
      default = "${config.home.homeDirectory}/.local/share/PrismLauncher/instances";
      description = "PrismLauncher のインスタンス置き場。";
    };

    outDir = lib.mkOption {
      type = lib.types.str;
      description = ''
        ZIP の出力先。空き容量のあるパーティションはホストごとに違うので既定値は置かず、
        呼び出し側で指定する。書き込み権限の用意も呼び出し側の責任。
      '';
    };

    remote = lib.mkOption {
      type = lib.types.str;
      description = "rclone の送り先 (例: gdrive:minecraft-backups)。";
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [
      (pkgs.writeShellApplication {
        name = "mc-backup";
        runtimeInputs = with pkgs; [ zip rclone procps ];
        runtimeEnv = {
          MC_BACKUP_INSTANCES = cfg.instancesDir;
          MC_BACKUP_OUT = cfg.outDir;
          MC_BACKUP_REMOTE = cfg.remote;
        };
        text = builtins.readFile ./minecraft-backup.sh;
      })
    ];
  };
}
