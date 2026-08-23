# PrismLauncher のインスタンスを restic で世代管理し、Google Drive へ写すコマンド群を提供する。
#
#   mc-backup   インスタンスを手元のリポジトリに取り込み、Drive へ写す (post-exit フック)
#   mc-check    他のマシンが新しい状態を持っていないか確かめる (pre-launch フック)
#   mc-restore  別のマシンが Drive に置いた状態をこのマシンへ取り込む (手動)
#   mc-sync     世代の刈り込みと、失敗した転送の取り直し (毎日のタイマー)
#
# 使い方:   docs/howtouse/minecraft-backup.md
# 設計判断: docs/architecture/minecraft-backup.md
{ config, pkgs, lib, ... }:

let
  cfg = config.local.minecraftBackup;

  # 4 つのコマンドは同じ共通部分と同じ環境を共有する。共通部分はファイルの先頭に連結する。
  mkCommand = name: body: pkgs.writeShellApplication {
    inherit name;
    runtimeInputs = with pkgs; [ restic rclone jq procps coreutils gnugrep ];
    runtimeEnv = {
      MC_INSTANCES = cfg.instancesDir;
      MC_REPO = cfg.repoDir;
      MC_REMOTE = cfg.remote;
      MC_RETENTION = lib.concatStringsSep " " cfg.retention;
      MC_WARN_GIB = toString cfg.warnAtGiB;
    };
    text = builtins.readFile ./minecraft-common.sh + builtins.readFile body;
  };

  mcBackup = mkCommand "mc-backup" ./minecraft-backup.sh;
  mcCheck = mkCommand "mc-check" ./minecraft-check.sh;
  mcRestore = mkCommand "mc-restore" ./minecraft-restore.sh;
  mcSync = mkCommand "mc-sync" ./minecraft-sync.sh;
in
{
  options.local.minecraftBackup = {
    enable = lib.mkEnableOption "PrismLauncher インスタンスの世代管理と Drive への同期";

    instancesDir = lib.mkOption {
      type = lib.types.str;
      default = "${config.home.homeDirectory}/.local/share/PrismLauncher/instances";
      description = "PrismLauncher のインスタンス置き場。";
    };

    repoDir = lib.mkOption {
      type = lib.types.str;
      description = ''
        restic リポジトリの置き場所。ここが正本で、Drive は写しになる。
        空き容量のあるパーティションはホストごとに違うので既定値は置かず、
        呼び出し側で指定する。書き込み権限の用意も呼び出し側の責任。
      '';
    };

    remote = lib.mkOption {
      type = lib.types.str;
      description = ''
        rclone での送り先の親ディレクトリ (例: gdrive:minecraft-backups)。
        この下にホスト名でリポジトリを分ける。2 台が同じリポジトリへ書くと、
        後から走った側の rclone sync が相手の世代を消してしまうため。
      '';
    };

    retention = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "--keep-last=3" "--keep-daily=14" "--keep-weekly=8" "--keep-monthly=12" ];
      description = "restic forget に渡す保持ポリシー。インスタンスごとに適用される。";
    };

    warnAtGiB = lib.mkOption {
      type = lib.types.int;
      default = 10;
      description = ''
        リポジトリがこの大きさを超えたら mc-sync が警告する。
        自動削除はしない。保持ポリシーと綱引きになるため。
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [ mcBackup mcCheck mcRestore mcSync ];

    systemd.user.services.mc-sync = {
      Unit.Description = "Minecraft バックアップの刈り込みと Drive への同期";
      Service = {
        Type = "oneshot";
        ExecStart = lib.getExe mcSync;
      };
    };

    systemd.user.timers.mc-sync = {
      Unit.Description = "Minecraft バックアップの刈り込みと Drive への同期";
      Timer = {
        OnCalendar = "daily";
        # 電源が入っていなかった日の分を起動後に走らせる。
        Persistent = true;
        RandomizedDelaySec = "10m";
      };
      Install.WantedBy = [ "timers.target" ];
    };
  };
}
