# papis ライブラリの Google Drive 同期の実体。default.nix が feature フラグ経由でのみ import する。
#
# 秘密（rclone.conf）は sops-nix ホームモジュールが復号し、その復号先パスを
# config.sops.secrets."rclone_conf".path として提供する。同期スクリプトはこの
# 属性だけを参照し、/run/secrets のような具体パスをどこにもハードコードしない
# （提供側=sops、消費側=同期スクリプトの依存性逆転）。
{ pkgs, lib, config, ... }:

let
  homeDir = config.home.homeDirectory;

  # papis ライブラリの実体（info.yaml と PDF が item ごとに同居する）。app.nix の
  # libraries.library.settings.dir と同一パスにすること。この 1 フォルダを丸ごと
  # bisync することで、メタデータ（平文 yaml）も PDF バイトも 1 系統で同期できる。
  libraryDir = "${homeDir}/papis-library";

  # rclone リモート。名前は人間が `rclone config` で作る remote 名と一致させる契約。
  remoteName = "gdrive";
  remoteFolder = "papis-library";
  remote = "${remoteName}:${remoteFolder}";

  # 復号済み rclone.conf のパス（単一の真実源）。プラットフォーム差は sops-nix が吸収する。
  rcloneConf = config.sops.secrets."rclone_conf".path;

  # 双方向同期本体。--resync の誤用（既存ベースラインの上書き）をガードする。
  papisSync = pkgs.writeShellApplication {
    name = "papis-sync";
    runtimeInputs = [ pkgs.rclone ];
    text = ''
      baseline_dir="''${XDG_CACHE_HOME:-$HOME/.cache}/rclone/bisync"

      resync=false
      for arg in "$@"; do
        if [ "$arg" = "--resync" ]; then
          resync=true
        fi
      done

      if [ "$resync" = true ] && [ "''${PAPIS_FORCE_RESYNC:-}" != "1" ]; then
        shopt -s nullglob dotglob
        existing=("$baseline_dir"/*)
        if [ "''${#existing[@]}" -gt 0 ]; then
          echo "papis-sync: bisync のベースラインが既に存在します（$baseline_dir）。" >&2
          echo "  誤操作による上書きを防ぐため --resync を中止しました。" >&2
          echo "  意図的にやり直す場合のみ PAPIS_FORCE_RESYNC=1 を付けて再実行してください。" >&2
          exit 1
        fi
      fi

      exec rclone --config ${rcloneConf} bisync \
        ${libraryDir} ${remote} \
        --conflict-resolve newer --resilient --verbose "$@"
    '';
  };

  # watcher の起動ラッパー。監視対象ディレクトリが未作成なら正常終了(0)して
  # クラッシュループを避ける（このモジュールは papis ライブラリを所有せず、
  # ライブラリは `papis add` が初めて作る）。
  papisWatch = pkgs.writeShellApplication {
    name = "papis-watch";
    runtimeInputs = [ pkgs.watchexec papisSync ];
    text = ''
      if [ ! -d "${libraryDir}" ]; then
        echo "papis-watch: ${libraryDir} が未作成のため監視を開始しません。papis add でライブラリを作成後に再起動してください。" >&2
        exit 0
      fi

      exec watchexec \
        --watch ${libraryDir} \
        --debounce 5s \
        --on-busy-update queue \
        -- papis-sync
    '';
  };
in
{
  sops.defaultSopsFile = ../../../secrets/rclone.yaml;
  # 各マシンのユーザ SSH 鍵を age に変換して復号に使う（新しい鍵を配らない運用）。
  sops.age.sshKeyPaths = [ "${homeDir}/.ssh/id_ed25519" ];
  sops.secrets."rclone_conf".mode = "0400";

  # rclone は modules/home-manager/rclone.nix で導入済み。watchexec は papisWatch に
  # 埋め込み済みなので、手動実行用の papis-sync だけをプロファイルに出す。
  home.packages = [ papisSync ];

  systemd.user.services.papis-watch = lib.mkIf pkgs.stdenv.isLinux {
    Unit = {
      Description = "papis ライブラリを監視して Google Drive へ bisync する";
      After = [ "sops-nix.service" ];
      Wants = [ "sops-nix.service" ];
    };
    Service = {
      ExecStart = "${papisWatch}/bin/papis-watch";
      Restart = "on-failure";
      RestartSec = 10;
    };
    Install.WantedBy = [ "default.target" ];
  };

  launchd.agents.papis-watch = lib.mkIf pkgs.stdenv.isDarwin {
    enable = true;
    config = {
      ProgramArguments = [ "${papisWatch}/bin/papis-watch" ];
      RunAtLoad = true;
      KeepAlive.SuccessfulExit = false;
      StandardErrorPath = "${homeDir}/Library/Logs/papis-watch.log";
      StandardOutPath = "${homeDir}/Library/Logs/papis-watch.log";
    };
  };
}
