# X のいいねの保存と意味検索（x-likes-archive）を動かす環境と定期実行。
#
#   xlikes          x-likes-archive の CLI を x-likes-env の中で実行する
#   x-likes-env     uv と ROCm 版の torch を動かす FHS 環境
#   xlikes-sync     いいね欄と引用元を取得して登録する（毎時）
#   xlikes-process  OCR と埋め込みの計算（毎晩）
#
# データベースは modules/nixos/x-likes.nix が、保存先のマウントはホストが用意する。
# 設計判断: docs/architecture/x-likes.md
# 使い方:   docs/howtouse/x-likes.md
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.local.xLikes;
  absolutePath = lib.types.strMatching "/.*";

  env = pkgs.callPackage ../../packages/x-likes-env {
    inherit (cfg) dataDir database hsaOverrideGfxVersion;
  };

  xlikes = pkgs.writeShellApplication {
    name = "xlikes";
    runtimeInputs = [ env ];
    text = ''
      exec x-likes-env uv run --project ${lib.escapeShellArg cfg.projectDir} --extra ml --frozen xlikes "$@"
    '';
  };

  # 本文の埋め込みを先に済ませ、時間のかかる OCR と画像の埋め込みはその後に回す。OCR の文字は
  # ruri の入力に入るので、最後にもう一度本文を埋め込む（入力が変わったツイートだけが計算される）。
  # 途中の手順が失敗しても残りは進め、最後に失敗として終わる。
  process = pkgs.writeShellApplication {
    name = "xlikes-process";
    runtimeInputs = [ xlikes ];
    text = ''
      status=0
      xlikes embed text || status=1
      xlikes ocr || status=1
      xlikes embed images || status=1
      xlikes embed text || status=1
      exit "$status"
    '';
  };
in
{
  options.local.xLikes = {
    enable = lib.mkEnableOption "X のいいねの保存と意味検索";

    dataDir = lib.mkOption {
      type = absolutePath;
      description = ''
        マウント済みの保存先。取得したツイート、uv の環境、モデルのチェックポイントを置く。
        マウントされていない間、x-likes-env は何も実行せずに止まる。
      '';
    };

    projectDir = lib.mkOption {
      type = absolutePath;
      description = "x-likes-archive の checkout。xlikes はここの uv.lock に従って環境を作る。";
    };

    database = lib.mkOption {
      type = lib.types.str;
      default = "xlikes";
      description = "Postgres のデータベース名。NixOS 側がこの名前でユーザー所有のデータベースを作る。";
    };

    hsaOverrideGfxVersion = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Optional ROCm GPU compatibility version.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = pkgs.stdenv.isLinux;
        message = "local.xLikes は systemd user timer と ROCm を使うので Linux でのみ動く。";
      }
    ]
    ++ map (name: {
      assertion = lib.hasPrefix "${config.home.homeDirectory}/" cfg.${name};
      message = "local.xLikes.${name} は自分の home の下に置く: ${cfg.${name}}";
    }) [ "dataDir" "projectDir" ];

    home.packages = [
      env
      xlikes
    ];

    systemd.user.services.xlikes-sync = {
      Unit = {
        Description = "X のいいね欄と引用元を取得して登録する";
        OnFailure = config.local.failureNotify.onFailure;
      };
      Service = {
        Type = "oneshot";
        # projectDir を更新したときのスキーマの変更も、次の実行で適用される。
        ExecStartPre = "${lib.getExe xlikes} migrate";
        ExecStart = "${lib.getExe xlikes} sync";
      };
    };

    systemd.user.timers.xlikes-sync = {
      Unit.Description = "X のいいね欄を毎時取得する";
      Timer.OnCalendar = "hourly";
      Install.WantedBy = [ "timers.target" ];
    };

    systemd.user.services.xlikes-process = {
      Unit = {
        Description = "保存したツイートの OCR と埋め込みを計算する";
        OnFailure = config.local.failureNotify.onFailure;
      };
      Service = {
        Type = "oneshot";
        ExecStartPre = "${lib.getExe xlikes} migrate";
        ExecStart = lib.getExe process;
        # OCR は CPU の全コアを使う。初回の取り込みが昼まで続いても、前面のアプリを遅くしないようにする。
        Nice = 19;
        IOSchedulingClass = "idle";
      };
    };

    systemd.user.timers.xlikes-process = {
      Unit.Description = "OCR と埋め込みを毎晩計算する";
      Timer = {
        # GPU を使うので、ゲームと重なりにくい時刻にする。電源が切れていて逃した分は、ユーザーのサービス
        # マネージャーが次に起動したとき（linger なら OS の起動時、そうでなければログイン時）に実行される。
        OnCalendar = "*-*-* 04:00:00";
        Persistent = true;
      };
      Install.WantedBy = [ "timers.target" ];
    };
  };
}
