# X のいいねとブックマークの保存と意味検索（xsaved）を動かす環境と定期実行。
#
#   xsaved          CLI を xsaved-env の中で実行する
#   xsaved-env      uv と ROCm 版の torch を動かす FHS 環境
#   xsaved-sync     いいね欄とブックマーク欄、返信先と引用元を取得して登録する（毎時）
#   xsaved-process  OCR と埋め込みの計算（毎晩）
#   xsaved-backup   取得したツイート、データベース、埋め込みモデルを restic で写す（毎日、backup.repository を設定したとき）
#   xsaved-restore-check  最新のバックアップから復元できるかを、保存先を変えずに確かめる
#   xsaved-update   定期実行を止め、バックアップを取ってから、本番用の checkout に新しいコミットを取り込む
#   xsaved-web      検索の Web UI。ブラウザで開いたときに起動し、使われなくなると止まる
#
# データベースと GPU のロックファイルは modules/nixos/xsaved.nix が用意する。保存先を subvol に
# するかはホストが決め、マウントを定義したときだけ xsaved-env がマウントを確かめる。
# 設計判断: docs/architecture/xsaved.md
# 使い方:   docs/howtouse/xsaved.md
{
  config,
  inputs,
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

  # 書き込むサブコマンドは共有ロック、xsaved-backup は排他ロックを取る。ユーザーごとに別のデータなので、
  # ロックファイルもユーザーごとの XDG_RUNTIME_DIR に置く。
  writeLock = ''"''${XDG_RUNTIME_DIR:?}/xsaved-write.lock"'';

  xsaved = pkgs.writeShellApplication {
    name = "xsaved";
    runtimeInputs = [
      env
      pkgs.util-linux
    ];
    # 埋め込みと OCR を使うサブコマンドだけに ml の依存（ROCm 版の torch など）を入れる。ほかのサブコマンドにも
    # 付けると、torch の取得や更新に失敗したときにツイートの取得と登録まで止まる。uv run は --exact を
    # 付けなければ venv から ml のパッケージを消さないので、venv は分けずに済む。
    text = ''
      case "''${1-}" in
        ocr | embed | tag | search | serve) extra=(--extra ml) ;;
        *) extra=() ;;
      esac
      run=(xsaved-env uv run --project ${lib.escapeShellArg cfg.projectDir} "''${extra[@]}" --frozen xsaved "$@")
      case "''${1-}" in
        # 読むだけのサブコマンドはロックを取らない。serve は何時間も動くので、取るとバックアップが始まらない。
        status | search | similar | serve) exec "''${run[@]}" ;;
        *) exec flock --shared ${writeLock} "''${run[@]}" ;;
      esac
    '';
  };

  # 本文の埋め込みを先に済ませ、時間のかかる OCR、画像の埋め込み、タグ付けはその後に回す。OCR の文字は
  # 本文の入力に入るので、最後にもう一度本文を埋め込む（入力が変わったツイートだけが計算される）。
  # 途中の手順が失敗しても残りは進め、最後に失敗として終わる。
  process = pkgs.writeShellApplication {
    name = "xsaved-process";
    runtimeInputs = [ xsaved ];
    text = ''
      status=0
      xsaved embed text || status=1
      xsaved ocr || status=1
      xsaved embed images || status=1
      xsaved tag || status=1
      xsaved tag-names || status=1
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
      pkgs.git
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

      # 取得や計算が書き込んでいる途中で写すと、データベースのダンプとファイルが別の時点の状態になる。
      # 書き込んでいるサブコマンドが終わるのを待ち、写し終えるまで新しく始めさせない。
      exec 9>${writeLock}
      flock 9

      # OCR と埋め込みの結果も入るので、データベースは丸ごと写す。復元すれば計算し直さずに済む。
      # 圧縮しない形式にして、restic が前の日の写しと重なる部分を再利用できるようにする。
      mkdir -p "$data/backup"
      pg_dump --host=/run/postgresql --dbname=${lib.escapeShellArg cfg.database} --no-owner \
        --file="$data/backup/xsaved.sql.tmp"
      mv "$data/backup/xsaved.sql.tmp" "$data/backup/xsaved.sql"

      # 復元したデータを、どのコードと設定が作ったか分かるようにする。
      app=${lib.escapeShellArg cfg.projectDir}
      xsaved_rev=$(git -C "$app" rev-parse HEAD 2>/dev/null || echo unknown)
      if [ -n "$(git -C "$app" status --porcelain 2>/dev/null)" ]; then xsaved_rev="$xsaved_rev-dirty"; fi
      printf 'flake_public %s\nxsaved %s\n' ${lib.escapeShellArg (inputs.self.rev or inputs.self.dirtyRev or "unknown")} "$xsaved_rev" \
        >"$data/backup/revisions"

      # 配布元がモデルを消すと同じモデルを取り直せず、保存済みのベクトルと比べる検索ができなくなるので、
      # モデルも写す。uv の環境は uv.lock から作り直せるので写さない。
      paths=("$data/tweets" "$data/backup/xsaved.sql" "$data/backup/revisions")
      if [ -d "$data/huggingface/hub" ]; then paths+=("$data/huggingface/hub"); fi

      restic cat config >/dev/null 2>&1 || restic init
      restic backup --tag xsaved "''${paths[@]}"
      flock --unlock 9
      restic forget --tag xsaved --keep-daily 7 --keep-weekly 4 --keep-monthly 12 --prune
    '';
  };

  # 新しいコミットは次の定期実行の起動時に migrate でスキーマを変えるので、取り込む直前の状態を写しておく。
  update = pkgs.writeShellApplication {
    name = "xsaved-update";
    runtimeInputs = [
      pkgs.git
      pkgs.util-linux
      osConfig.systemd.package
      xsaved
    ];
    text = ''
      app=${lib.escapeShellArg cfg.projectDir}
      if [ ! -d "$app/.git" ]; then
        echo "xsaved-update: $app がありません。開発用の checkout から git clone で作成してください（docs/howtouse/xsaved.md）" >&2
        exit 1
      fi
      units=(xsaved-sync.timer xsaved-process.timer ${lib.optionalString (cfg.backup.repository != null) "xsaved-backup.timer"} xsaved-web.socket)
      systemctl --user stop "''${units[@]}" xsaved-web-server.service
      trap 'systemctl --user start "''${units[@]}"' EXIT

      # バックアップは書き込みのロックを排他で取るので、動いている取得や計算が終わるのを待ってから写す。
      ${if cfg.backup.repository != null then ''
        systemctl --user start xsaved-backup.service
      '' else ''
        flock ${writeLock} true
      ''}
      before=$(git -C "$app" rev-parse HEAD)
      git -C "$app" pull --ff-only
      git -C "$app" log --oneline "$before..HEAD"
      xsaved migrate
    '';
  };

  restoreCheck = pkgs.writeShellApplication {
    name = "xsaved-restore-check";
    runtimeInputs = [
      pkgs.restic
      pkgs.rclone
      pkgs.coreutils
      pkgs.gnused
      osConfig.services.postgresql.finalPackage
    ];
    text = ''
      data=${lib.escapeShellArg cfg.dataDir}
      export RESTIC_REPOSITORY=${lib.escapeShellArg cfg.backup.repository}
      export RESTIC_PASSWORD_FILE=${lib.escapeShellArg cfg.backup.passwordFile}
      snapshot=(latest --tag xsaved)

      # ルートは空きが少なく、ダンプを読み込んだデータベースは数 GB になるので、保存先と同じディスクで試す。
      work=$(mktemp -d "$data/restore-check.XXXXXX")
      cleanup() {
        pg_ctl -D "$work/pg" -m fast stop >/dev/null 2>&1 || true
        rm -rf "$work"
      }
      trap cleanup EXIT

      restic snapshots --tag xsaved --latest 1
      restic restore "''${snapshot[@]}" --target "$work/files" --include "$data/backup" >/dev/null
      cat "$work/files$data/backup/revisions" 2>/dev/null || echo "このスナップショットにはコミットの記録がない"

      # 本番のデータベースに触れないよう、一時的な Postgres にダンプを読み込む。
      initdb -D "$work/pg" -U postgres --auth=trust -E UTF8 --locale=C.UTF-8 >/dev/null
      pg_ctl -D "$work/pg" -l "$work/pg.log" -w -o "-c listen_addresses=''' -c unix_socket_directories=$work" start >/dev/null
      psql=(psql -h "$work" -U postgres -X -q -v ON_ERROR_STOP=1)
      "''${psql[@]}" -d postgres -c 'CREATE DATABASE restored'
      "''${psql[@]}" -d restored -f "$work/files$data/backup/xsaved.sql" >/dev/null
      q() { "''${psql[@]}" -d restored -At -c "$1"; }

      echo "いいね $(q 'SELECT count(*) FROM tweets WHERE liked')、ブックマーク $(q 'SELECT count(*) FROM tweets WHERE bookmarked')、ツイート全体 $(q 'SELECT count(*) FROM tweets')"
      echo "引用 $(q 'SELECT count(*) FROM quotes')、返信 $(q 'SELECT count(*) FROM replies')、メディア $(q 'SELECT count(*) FROM media')"
      echo "ベクトル: ruri $(q 'SELECT count(*) FROM tweet_ruri')、Qwen の本文 $(q 'SELECT count(*) FROM tweet_qwen')、Qwen の画像 $(q 'SELECT count(*) FROM image_qwen')"
      # 読み込んだデータで、全文検索の索引とベクトルの比較が使えることを確かめる。
      echo "全文検索で「の」を含むツイート $(q "SET enable_seqscan = off; SELECT count(*) FROM tweets WHERE search_text &@~ 'の'") 件"
      echo "ベクトル検索の結果 $(q 'SELECT count(*) FROM (SELECT tweet_id FROM tweet_ruri ORDER BY embedding <=> (SELECT embedding FROM tweet_ruri LIMIT 1) LIMIT 10) s') 件"

      # メディアを全部戻す空きはないので、全ファイルがスナップショットにあることを一覧で確かめ、
      # 一部だけ戻して中身をデータベースのハッシュと照合する。
      restic ls "''${snapshot[@]}" "$data/tweets/media" | sed -n "s|^$data/tweets/media/||p" | sort >"$work/listed"
      q 'SELECT path FROM media' | sort >"$work/expected"
      missing=$(comm -13 "$work/listed" "$work/expected" | wc -l)
      echo "データベースにあってスナップショットにないメディア $missing 件"
      q 'SELECT path, sha256 FROM media ORDER BY random() LIMIT 20' | tr '|' ' ' >"$work/sample"
      includes=()
      while read -r path _; do includes+=(--include "$data/tweets/media/$path"); done <"$work/sample"
      restic restore "''${snapshot[@]}" --target "$work/files" "''${includes[@]}" >/dev/null
      mismatched=0
      while read -r path sha; do
        if [ "$(sha256sum "$work/files$data/tweets/media/$path" | cut -d' ' -f1)" != "$sha" ]; then
          echo "中身が一致しない: $path"
          mismatched=$((mismatched + 1))
        fi
      done <"$work/sample"
      echo "戻して照合したメディア $(wc -l <"$work/sample") 件、一致しないもの $mismatched 件"
      echo "モデル: $(restic ls "''${snapshot[@]}" "$data/huggingface/hub" | sed -n "s|^$data/huggingface/hub/\(models--[^/]*\)$|\1|p" | tr '\n' ' ')"

      [ "$missing" -eq 0 ] && [ "$mismatched" -eq 0 ]
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
      update
    ] ++ lib.optional (cfg.backup.repository != null) restoreCheck;

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
