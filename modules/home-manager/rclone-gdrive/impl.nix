# rclone-gdrive の実体。default.nix が feature フラグ経由でのみ import する。
#
# 秘密（rclone.conf）は sops-nix ホームモジュールが復号し、その復号先パスを
# config.sops.secrets."rclone_conf".path として提供する。同期スクリプトはこの
# 属性だけを参照し、/run/secrets のような具体パスをどこにもハードコードしない
# （提供側=sops、消費側=同期スクリプトの依存性逆転）。
{ pkgs, lib, config, ... }:

let
  homeDir = config.home.homeDirectory;

  # Zotero のリンク添付ベースディレクトリ（人間が Zotero 側で同じ値に設定する）。
  pdfDir = "${homeDir}/Zotero-PDFs";

  # rclone リモート。名前は人間が `rclone config` で作る remote 名と一致させる契約。
  remoteName = "gdrive";
  remoteFolder = "Zotero-PDFs";
  remote = "${remoteName}:${remoteFolder}";

  # 復号済み rclone.conf のパス（単一の真実源）。プラットフォーム差は sops-nix が吸収する。
  rcloneConf = config.sops.secrets."rclone_conf".path;

  # 双方向同期本体。--resync の誤用（既存ベースラインの上書き）をガードする。
  zoteroSync = pkgs.writeShellApplication {
    name = "zotero-sync";
    runtimeInputs = [ pkgs.rclone ];
    text = ''
      baseline_dir="''${XDG_CACHE_HOME:-$HOME/.cache}/rclone/bisync"

      resync=false
      for arg in "$@"; do
        if [ "$arg" = "--resync" ]; then
          resync=true
        fi
      done

      if [ "$resync" = true ] && [ "''${ZOTERO_FORCE_RESYNC:-}" != "1" ]; then
        shopt -s nullglob dotglob
        existing=("$baseline_dir"/*)
        if [ "''${#existing[@]}" -gt 0 ]; then
          echo "zotero-sync: bisync のベースラインが既に存在します（$baseline_dir）。" >&2
          echo "  誤操作による上書きを防ぐため --resync を中止しました。" >&2
          echo "  意図的にやり直す場合のみ ZOTERO_FORCE_RESYNC=1 を付けて再実行してください。" >&2
          exit 1
        fi
      fi

      exec rclone --config ${rcloneConf} bisync \
        ${pdfDir} ${remote} \
        --conflict-resolve newer --resilient --verbose "$@"
    '';
  };

  # watcher の起動ラッパー。監視対象ディレクトリが未作成なら正常終了(0)して
  # クラッシュループを避ける（このモジュールは Zotero のデータディレクトリを所有しない）。
  zoteroWatch = pkgs.writeShellApplication {
    name = "zotero-watch";
    runtimeInputs = [ pkgs.watchexec zoteroSync ];
    text = ''
      if [ ! -d "${pdfDir}" ]; then
        echo "zotero-watch: ${pdfDir} が未作成のため監視を開始しません。Zotero 設定後に再起動してください。" >&2
        exit 0
      fi

      exec watchexec \
        --watch ${pdfDir} \
        --debounce 5s \
        --on-busy-update queue \
        -- zotero-sync
    '';
  };
in
{
  sops.defaultSopsFile = ../../../secrets/rclone.yaml;
  # 各マシンのユーザ SSH 鍵を age に変換して復号に使う（新しい鍵を配らない運用）。
  sops.age.sshKeyPaths = [ "${homeDir}/.ssh/id_ed25519" ];
  sops.secrets."rclone_conf".mode = "0400";

  # rclone は modules/home-manager/rclone.nix で導入済み。watchexec は zoteroWatch に
  # 埋め込み済みなので、手動実行用の zotero-sync だけをプロファイルに出す。
  home.packages = [ zoteroSync ];

  systemd.user.services.zotero-watch = lib.mkIf pkgs.stdenv.isLinux {
    Unit = {
      Description = "Zotero PDF フォルダを監視して Google Drive へ bisync する";
      After = [ "sops-nix.service" ];
      Wants = [ "sops-nix.service" ];
    };
    Service = {
      ExecStart = "${zoteroWatch}/bin/zotero-watch";
      Restart = "on-failure";
      RestartSec = 10;
    };
    Install.WantedBy = [ "default.target" ];
  };

  launchd.agents.zotero-watch = lib.mkIf pkgs.stdenv.isDarwin {
    enable = true;
    config = {
      ProgramArguments = [ "${zoteroWatch}/bin/zotero-watch" ];
      RunAtLoad = true;
      KeepAlive.SuccessfulExit = false;
      StandardErrorPath = "${homeDir}/Library/Logs/zotero-watch.log";
      StandardOutPath = "${homeDir}/Library/Logs/zotero-watch.log";
    };
  };
}
