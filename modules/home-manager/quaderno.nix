# Quaderno A4 Gen2 から手書き PDF を取り込む。同じ LAN にいるときだけ動く。
#
#   quaderno-pull   未取得・改訂された文書をアーカイブへ落とす（タイマーと手動の両方）
#
# 一方向で、手元のファイルを消さない。デバイス側で削除された文書はアーカイブに残る。
# 設計判断: docs/architecture/quaderno.md
# 使い方:   docs/howtouse/quaderno.md
#
# 将来 zettelkasten-workflow へ移せるよう、このモジュールは local.quaderno と
# home.homeDirectory 以外の、このリポジトリに固有の値を読まない。
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.local.quaderno;
  absolutePath = lib.types.strMatching "/.*";

  dptrp1 = pkgs.callPackage ../../packages/dpt-rp1-py { };

  # dptrp1 を import できる Python。buildPythonApplication の出力はそのままでは
  # モジュールとして見えないので toPythonModule で包む。
  pythonEnv = pkgs.python3.withPackages (ps: [ (pkgs.python3Packages.toPythonModule dptrp1) ]);

  # 2 つのスクリプトを同じディレクトリに置く。Python は実行スクリプトのディレクトリを
  # sys.path に入れるので、quaderno_pull.py から quaderno_plan.py を import できる。
  scripts = pkgs.runCommand "quaderno-scripts" { } ''
    mkdir -p "$out"
    cp ${./quaderno_plan.py} "$out/quaderno_plan.py"
    cp ${./quaderno_pull.py} "$out/quaderno_pull.py"
  '';

  quaderno-pull = pkgs.writeShellApplication {
    name = "quaderno-pull";
    runtimeInputs = [ pythonEnv ];
    runtimeEnv = {
      # null は空文字で渡す。スクリプト側はこれを「指定なし」として扱う。
      QUADERNO_SERIAL = if cfg.serial == null then "" else cfg.serial;
      QUADERNO_ARCHIVE_DIR = cfg.archiveDir;
      QUADERNO_REMOTE_ROOT = cfg.remoteRoot;
      QUADERNO_DISCOVERY_TIMEOUT = toString cfg.discoveryTimeoutSeconds;
      QUADERNO_STATE_FILE = "${config.xdg.stateHome}/quaderno/state.json";
    };
    text = ''
      exec python3 ${scripts}/quaderno_pull.py "$@"
    '';
  };
in
{
  options.local.quaderno = {
    enable = lib.mkEnableOption "Quaderno からの取り込み";

    serial = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = ''
        接続する機器のシリアル番号。null なら mDNS で最初に見つかった Digital Paper に
        接続する。該当する機器が 1 台しかない環境では指定しなくてよい。

        同じ LAN に別の Digital Paper 系機器が現れて取り違えを避けたくなったときに書く。
        値は本体の Wi-Fi を入れた状態で
        `curl -s http://<IP>:8080/register/information` から読める。
        秘密ではない（同じ LAN にいれば認証なしで読める）。
      '';
    };

    archiveDir = lib.mkOption {
      type = absolutePath;
      description = ''
        取り込み先。デバイス上の相対パスをこの下に再現する。
        置き場所は環境ごとに違うので既定値は置かず、呼び出し側で指定する。
        ディレクトリの用意と書き込み権限も呼び出し側の責任。存在しない間は
        タイマーが何もせず skip する。
        ここが手動で Google Drive へ上げる単位になる。
      '';
    };

    remoteRoot = lib.mkOption {
      type = lib.types.str;
      default = "Document";
      description = "デバイス上の対象フォルダ。この配下だけを取り込む。";
    };

    intervalSeconds = lib.mkOption {
      type = lib.types.int;
      default = 3600;
      description = ''
        取り込みを試す間隔。Quaderno はスリープすると Wi-Fi ごと落ちるので、
        ほとんどの実行は相手を見つけられずに終わる。
      '';
    };

    discoveryTimeoutSeconds = lib.mkOption {
      type = lib.types.int;
      default = 15;
      description = "mDNS で機器を探す時間。この間に見つからなければ何もせず終わる。";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = pkgs.stdenv.isLinux;
        message = ''
          local.quaderno は systemd user timer を使うので Linux でのみ動く。
          macOS で使うには launchd 版の定義が要る。
        '';
      }
      {
        # home の外（/mnt の別ディスクなど）に置くのは許す。禁じたいのは他のユーザーの
        # home を指すことだけ。
        assertion =
          !(lib.hasPrefix "/home/" cfg.archiveDir)
          || lib.hasPrefix "${config.home.homeDirectory}/" cfg.archiveDir;
        message = ''
          local.quaderno.archiveDir が他のユーザーの home を指している: ${cfg.archiveDir}
        '';
      }
    ];

    # dptrp1 も PATH に出す。ペアリング未了・認証失敗の案内で
    # `dptrp1 --addr <IP> register` を指す先が実在するようにする。
    home.packages = [
      quaderno-pull
      dptrp1
    ];

    systemd.user.services.quaderno-pull = {
      Unit = {
        Description = "Quaderno から未取得の文書を取り込む";
        # 取り込み先がまだ無い間は失敗にせず skip する。用意するのは呼び出し側の責任で、
        # このホストでは data-disk.nix の systemd.tmpfiles が作る。
        ConditionPathIsDirectory = cfg.archiveDir;
      };
      Service = {
        Type = "oneshot";
        ExecStart = lib.getExe quaderno-pull;
      };
    };

    systemd.user.timers.quaderno-pull = {
      Unit.Description = "Quaderno の取り込みを定期的に試す";
      Timer = {
        OnActiveSec = "2min";
        OnUnitActiveSec = "${toString cfg.intervalSeconds}s";
      };
      Install.WantedBy = [ "timers.target" ];
    };
  };
}
