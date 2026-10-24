# X のいいねとブックマークの保存と意味検索（xsaved）を動かす環境と定期実行。
#
#   xsaved          CLI を xsaved-env の中で実行する
#   xsaved-env      uv と ROCm 版の torch を動かす FHS 環境
#   xsaved-sync     いいね欄とブックマーク欄、返信先と引用元を取得して登録する（毎時）
#   xsaved-process  OCR と埋め込みの計算（毎晩）
#   xsaved-backup   取得したツイートとデータベースを restic で写す（毎日、backup.repository を設定したとき）
#   xsaved-web      検索の Web UI。ブラウザで開いたときに起動し、使われなくなると止まる
#
# データベースと GPU のロックファイルは modules/nixos/xsaved.nix が用意する。保存先を subvol に
# するかはホストが決め、マウントを定義したときだけ xsaved-env がマウントを確かめる。
# 設計判断: docs/architecture/xsaved.md
# 使い方:   docs/howtouse/xsaved.md
{
  config,
  lib,
  osConfig,
  pkgs,
  ...
}:
let
  cfg = config.local.xsaved;
  absolutePath = lib.types.strMatching "/.*";
  # osConfig は NixOS のモジュールとして使うときだけある。単独で使う構成では assertion で止める。
  onNixos = config.submoduleSupport.enable;

  # dataDir を nofail でマウントするホストでは、マウントされていない間に何も書かず、何も写さない。
  checkMount = onNixos && osConfig.fileSystems ? ${cfg.dataDir};

  env = pkgs.callPackage ../../packages/xsaved-env {
    inherit (cfg) dataDir database hsaOverrideGfxVersion;
    inherit checkMount;
    gpuLock = if onNixos then osConfig.local.xsaved.gpuLock else null;
  };

  xsaved = pkgs.writeShellApplication {
    name = "xsaved";
    runtimeInputs = [ env ];
    # 埋め込みと OCR を使うサブコマンドだけに ml の依存（ROCm 版の torch など）を入れる。ほかのサブコマンドにも
    # 付けると、torch の取得や更新に失敗したときにツイートの取得と登録まで止まる。uv run は --exact を
    # 付けなければ venv から ml のパッケージを消さないので、venv は分けずに済む。
    text = ''
      case "''${1-}" in
        ocr | embed | search | serve) extra=(--extra ml) ;;
        *) extra=() ;;
      esac
      exec xsaved-env uv run --project ${lib.escapeShellArg cfg.projectDir} "''${extra[@]}" --frozen xsaved "$@"
    '';
  };

  # 本文の埋め込みを先に済ませ、時間のかかる OCR と画像の埋め込みはその後に回す。OCR の文字は
  # ruri の入力に入るので、最後にもう一度本文を埋め込む（入力が変わったツイートだけが計算される）。
  # 途中の手順が失敗しても残りは進め、最後に失敗として終わる。
  process = pkgs.writeShellApplication {
    name = "xsaved-process";
    runtimeInputs = [ xsaved ];
    text = ''
      status=0
      xsaved embed text || status=1
      xsaved ocr || status=1
      xsaved embed images || status=1
      xsaved embed text || status=1
      exit "$status"
    '';
  };

  # Web UI のサーバーは、ソケットの次のポートで待ち受け、systemd-socket-proxyd が要求を渡す。
  serverPort = toString (cfg.webPort + 1);
  waitForServer = pkgs.writeShellScript "xsaved-web-wait" ''
    until (exec 3<>/dev/tcp/127.0.0.1/${serverPort}) 2>/dev/null; do sleep 0.5; done
  '';

  backup = pkgs.writeShellApplication {
    name = "xsaved-backup";
    runtimeInputs = [
      pkgs.restic
      pkgs.rclone
      pkgs.util-linux
      osConfig.services.postgresql.package
    ];
    text = ''
      data=${lib.escapeShellArg cfg.dataDir}
      ${lib.optionalString checkMount ''
        # マウントされていない空のディレクトリを写すと、空の世代が日次の世代を押し出す。
        if ! mountpoint -q "$data"; then
          echo "xsaved-backup: $data がマウントされていません" >&2
          exit 1
        fi
      ''}
      export RESTIC_REPOSITORY=${lib.escapeShellArg cfg.backup.repository}
      export RESTIC_PASSWORD_FILE=${lib.escapeShellArg cfg.backup.passwordFile}

      # OCR と埋め込みの結果も入るので、データベースは丸ごと写す。復元すれば計算し直さずに済む。
      # 圧縮しない形式にして、restic が前の日の写しと重なる部分を再利用できるようにする。
      mkdir -p "$data/backup"
      pg_dump --host=/run/postgresql --dbname=${lib.escapeShellArg cfg.database} --no-owner \
        --file="$data/backup/xsaved.sql.tmp"
      mv "$data/backup/xsaved.sql.tmp" "$data/backup/xsaved.sql"

      restic cat config >/dev/null 2>&1 || restic init
      restic backup --tag xsaved "$data/tweets" "$data/backup/xsaved.sql"
      restic forget --tag xsaved --keep-daily 7 --keep-weekly 4 --keep-monthly 12 --prune
    '';
  };
in
{
  options.local.xsaved = {
    enable = lib.mkEnableOption "X のいいねとブックマークの保存と意味検索";

    dataDir = lib.mkOption {
      type = absolutePath;
      description = ''
        保存先。取得したツイート、uv の環境、モデルのチェックポイントを置く。
        NixOS 側でこのパスのマウントを定義したときは、マウントされていない間、xsaved-env は何も実行せずに止まる。
      '';
    };

    projectDir = lib.mkOption {
      type = absolutePath;
      description = "定期実行と xsaved コマンドが実行する、本番用の xsaved の checkout。xsaved はここの uv.lock に従って環境を作る。開発用の checkout とは分ける。";
    };

    database = lib.mkOption {
      # NixOS 側が superuser の SQL に、xsaved が接続文字列に、そのまま埋め込むので、引用符や空白を許さない。
      # Postgres が引用符なしで受け付ける識別子に限り、長さも識別子の上限の 63 バイトに収める。
      type = lib.types.strMatching "[a-z_][a-z0-9_]{0,62}";
      default = "xsaved";
      description = "Postgres のデータベース名。NixOS 側がこの名前でユーザー所有のデータベースを作る。";
    };

    hsaOverrideGfxVersion = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Optional ROCm GPU compatibility version.";
    };

    webPort = lib.mkOption {
      type = lib.types.port;
      default = 8765;
      description = ''
        Web UI を開くポート（127.0.0.1）。サーバー自身は次のポートで待ち受けるので、
        同じホストのほかのユーザーとは 2 つ以上離す。
      '';
    };

    backup = {
      repository = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        example = "rclone:gdrive:xsaved-backup";
        description = ''
          restic のリポジトリ。取得したツイートとデータベースのダンプを毎日写す。null なら写さない。
          X で消えたツイートは取り直せないので、保存先と別のディスクかクラウドに置く。
        '';
      };
      passwordFile = lib.mkOption {
        type = lib.types.nullOr absolutePath;
        default = null;
        description = "restic のリポジトリのパスワードを書いたファイル。";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = pkgs.stdenv.isLinux;
        message = "local.xsaved は systemd user timer と ROCm を使うので Linux でのみ動く。";
      }
      {
        assertion = onNixos;
        message = ''
          local.xsaved は NixOS の Home Manager モジュールとして使うときだけ有効にできる。
          拡張を作るには superuser が要るので、データベースは NixOS 側（modules/nixos/xsaved.nix）が作る。
        '';
      }
    ]
    ++ [
      {
        assertion = cfg.backup.repository == null || cfg.backup.passwordFile != null;
        message = "local.xsaved.backup.repository を設定したら、backup.passwordFile も設定する。";
      }
    ]
    ++ map (name: {
      assertion = lib.hasPrefix "${config.home.homeDirectory}/" cfg.${name};
      message = "local.xsaved.${name} は自分の home の下に置く: ${cfg.${name}}";
    }) [ "dataDir" "projectDir" ];

    home.packages = [
      env
      xsaved
    ];

    # 三つの定期実行は oneshot で、何時間も続くことがある。switch で定義が変わったときに Home Manager が
    # 起動し直すと、止めた処理をやり直し、終わるまで switch も返らない。動いている間は入れ替えず、
    # 次の実行から新しい定義を使う。
    systemd.user.services.xsaved-sync = {
      Unit = {
        Description = "X のいいねとブックマーク、返信先と引用元を取得して登録する";
        OnFailure = config.local.failureNotify.onFailure;
        X-SwitchMethod = "keep-old";
      };
      Service = {
        Type = "oneshot";
        # projectDir を更新したときのスキーマの変更も、次の実行で適用される。
        ExecStartPre = "${lib.getExe xsaved} migrate";
        ExecStart = "${lib.getExe xsaved} sync";
      };
    };

    systemd.user.timers.xsaved-sync = {
      Unit.Description = "X のいいねとブックマークを毎時取得する";
      Timer.OnCalendar = "hourly";
      Install.WantedBy = [ "timers.target" ];
    };

    systemd.user.services.xsaved-process = {
      Unit = {
        Description = "保存したツイートの OCR と埋め込みを計算する";
        OnFailure = config.local.failureNotify.onFailure;
        X-SwitchMethod = "keep-old";
      };
      Service = {
        Type = "oneshot";
        ExecStartPre = "${lib.getExe xsaved} migrate";
        ExecStart = lib.getExe process;
        # OCR は CPU の全コアを使う。初回の取り込みが昼まで続いても、前面のアプリを遅くしないようにする。
        Nice = 19;
        IOSchedulingClass = "idle";
      };
    };

    systemd.user.timers.xsaved-process = {
      Unit.Description = "OCR と埋め込みを毎晩計算する";
      Timer = {
        # GPU を使うので、ゲームと重なりにくい時刻にする。電源が切れていて逃した分は、ユーザーのサービス
        # マネージャーが次に起動したとき（linger なら OS の起動時、そうでなければログイン時）に実行される。
        OnCalendar = "*-*-* 04:00:00";
        Persistent = true;
      };
      Install.WantedBy = [ "timers.target" ];
    };

    # 検索はときどき使うだけなので、モデルを VRAM に載せたまま常駐させない。ブラウザで開くとソケットから
    # サーバーが起動し、15 分要求がなければ systemd-socket-proxyd が終わり、サーバーも止まって VRAM を返す。
    systemd.user.sockets.xsaved-web = {
      Unit.Description = "保存したツイートの検索の Web UI を待ち受ける";
      Socket.ListenStream = "127.0.0.1:${toString cfg.webPort}";
      Install.WantedBy = [ "sockets.target" ];
    };

    systemd.user.services.xsaved-web = {
      Unit = {
        Description = "Web UI への要求を検索のサーバーへ渡す";
        BindsTo = [ "xsaved-web-server.service" ];
        After = [ "xsaved-web-server.service" ];
      };
      Service.ExecStart =
        "${osConfig.systemd.package}/lib/systemd/systemd-socket-proxyd --exit-idle-time=15min 127.0.0.1:${serverPort}";
    };

    systemd.user.services.xsaved-web-server = {
      Unit = {
        Description = "保存したツイートの検索のサーバー";
        StopWhenUnneeded = true;
      };
      Service = {
        ExecStart = "${lib.getExe xsaved} serve --port ${serverPort}";
        # 待ち受けを始めるまで、プロキシを起動させない。uv が環境を作り直すときは数分かかる。
        ExecStartPost = waitForServer;
        TimeoutStartSec = "5min";
      };
    };

    systemd.user.services.xsaved-backup = lib.mkIf (cfg.backup.repository != null) {
      Unit = {
        Description = "取得したツイートとデータベースを restic で写す";
        OnFailure = config.local.failureNotify.onFailure;
        X-SwitchMethod = "keep-old";
      };
      Service = {
        Type = "oneshot";
        ExecStart = lib.getExe backup;
        Nice = 10;
        IOSchedulingClass = "idle";
      };
    };

    systemd.user.timers.xsaved-backup = lib.mkIf (cfg.backup.repository != null) {
      Unit.Description = "取得したツイートとデータベースを毎日写す";
      Timer = {
        # 夜間の OCR と埋め込みのあとにして、その日の計算結果まで写す。
        OnCalendar = "*-*-* 06:00:00";
        Persistent = true;
      };
      Install.WantedBy = [ "timers.target" ];
    };
  };
}
