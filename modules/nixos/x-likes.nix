# X のいいねの保存（Home Manager の local.xLikes）を有効にしたユーザーに、Postgres のデータベースを用意する。
# データベースはそのユーザーが所有し、Unix socket の peer 認証で接続する。
# GPU を使う計算は、全ユーザーで共有するロックファイルで順番にする。
# 設計判断: docs/architecture/x-likes.md
{
  config,
  lib,
  pkgs,
  ...
}:
let
  databases = lib.mapAttrsToList (owner: hm: {
    inherit owner;
    name = hm.local.xLikes.database;
  }) (lib.filterAttrs (_: hm: hm.local.xLikes.enable) config.home-manager.users);
in
{
  options.local.xLikes.gpuLock = lib.mkOption {
    type = lib.types.str;
    readOnly = true;
    default = "/run/x-likes-gpu.lock";
    description = ''
      xlikes embed が排他ロックを取るファイル。local.xLikes を有効にしたユーザー全員が同じファイルを使い、
      GPU を使う計算を順番にする。
    '';
  };

  config = lib.mkIf (databases != [ ]) {
    assertions = [
      {
        assertion = lib.allUnique (map (db: db.name) databases);
        message = "local.xLikes.database はユーザーごとに別の名前にする。";
      }
    ];

    services.postgresql = {
      enable = true;
      # メジャー版を上げるとデータディレクトリの移行が要るので、stateVersion に連動させず固定する。
      package = pkgs.postgresql_17;
      extensions = ps: [
        ps.pgvector
        ps.pgroonga
      ];
      ensureDatabases = map (db: db.name) databases;
      ensureUsers = map (db: { name = db.owner; }) databases;
    };

    # flock は読み取りで開いたファイルにも掛けられるので、root が持つ 0644 のファイルで全ユーザーが使える。
    systemd.tmpfiles.rules = [ "f ${config.local.xLikes.gpuLock} 0644 root root -" ];

    # ensureDBOwnership はユーザーと同じ名前のデータベースにしか使えないので、所有者はここで付ける。
    # 二つの拡張は trusted ではなく、所有者（superuser でないロール）には作れないので、ここで作っておく。
    systemd.services.postgresql-setup.script = lib.mkAfter (
      lib.concatMapStrings (db: ''
        psql -tAc 'ALTER DATABASE "${db.name}" OWNER TO "${db.owner}"'
        psql -d ${lib.escapeShellArg db.name} -tAc 'CREATE EXTENSION IF NOT EXISTS vector; CREATE EXTENSION IF NOT EXISTS pgroonga'
      '') databases
    );
  };
}
