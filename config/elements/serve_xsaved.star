# 目的: 自分用サーバとして xsaved を公開する。X のいいねとブックマークを集めて保管し、検索の Web UI を動かす（サーバの側。docs/howtouse/xsaved.md）。
def _quote(value):
    return "'" + value.replace("'", "'\"'\"'") + "'"

def _database(value):
    if not value or len(value) > 63 or value[0] not in "abcdefghijklmnopqrstuvwxyz_" or any([c not in "abcdefghijklmnopqrstuvwxyz_0123456789" for c in value.elems()]):
        fail("xsaved: invalid database identifier")
    return value

needs = ["nixos_system"]
requires = ["xsaved_data", "xsaved_web_proxy", "xsaved_backup"]
role = True

_GPU_LOCK = "/run/xsaved-gpu.lock"
_DEFAULT_PORT = 8765

# 利用者ごとの値は、ホストのファイルの利用者の表（[[users]] の直後の [users.xsaved]）に書く。
# データと本番用の checkout の場所は、利用者のホームから決める。
def public(user):
    values = getattr(user, "xsaved", None)
    if values == None:
        fail("xsaved: user " + user.name + " selects xsaved but has no [users.xsaved] table in the host file")
    port = values.get("web_port", _DEFAULT_PORT)
    if type(port) != "int" or port < 1 or port > 65535:
        fail("xsaved: invalid web port")
    return {
        "data_dir": user.home + "/.local/share/xsaved",
        "project_dir": user.home + "/.local/share/xsaved-app",
        "database": _database(values.get("database", "xsaved")),
        "web_port": port,
        "check_mount": values.get("check_mount", False),
        "values": values,
        "gpu_lock": _GPU_LOCK,
        # メジャー版を上げるとデータディレクトリの移行が要るので、stateVersion に連動させない。
        "postgresql": pkg("postgresql_17"),
        "postgresql_extensions": pkgWithPackages("postgresql_17", ["pgvector", "pgroonga"]),
        "systemd": pkg("systemd"),
    }

def config(host):
    tables = [account["xsaved"] for account in host.users if "xsaved" in account]
    # データベースとポートは機体で共有するので、利用者どうしで重ならないことを確かめる。
    for key, default in [("database", "xsaved"), ("web_port", _DEFAULT_PORT)]:
        chosen = [table.get(key, default) for table in tables]
        if len(chosen) != len({str(value): True for value in chosen}):
            fail("xsaved: " + key + " must be unique per user")
    nixos = {
        "services.postgresql.enable": True,
        "services.postgresql.package": pkg("postgresql_17"),
        "services.postgresql.extensions": pkgSetFn(["pgvector", "pgroonga"]),
        "systemd.tmpfiles.rules": ["f " + _GPU_LOCK + " 0644 root root -"],
    }
    return {"nixos": nixos}

def user_config(user, serve_xsaved, failure_notify):
    xsaved = serve_xsaved
    values = xsaved.values
    data = xsaved.data_dir
    project = xsaved.project_dir
    database = xsaved.database
    port = xsaved.web_port
    check_mount = xsaved.check_mount
    env = repoPkgWith("packages/xsaved-env", {
        "dataDir": data,
        "database": database,
        "hsaOverrideGfxVersion": values.get("hsa_override", None),
        "checkMount": check_mount,
        "gpuLock": xsaved.gpu_lock,
    })
    cli = shellAppEnv("xsaved", [env, pkg("util-linux")], {"XSAVED_PROJECT_DIR": project}, repoText("modules/home-manager/xsaved/xsaved.sh"))
    cli_exe = concat(cli, "/bin/xsaved")
    process = shellApp("xsaved-process", [cli, xsaved.systemd], repoText("modules/home-manager/xsaved/process.sh"))
    # 更新の前に、xsaved_backup の xsaved-backup.service でバックアップを取る。
    update = shellAppEnv("xsaved-update", [pkg("git"), pkg("util-linux"), xsaved.systemd, cli], {
        "XSAVED_PROJECT_DIR": project,
    }, repoText("modules/home-manager/xsaved/update.sh"))
    home = {"home.packages": [env, cli, update]}
    # 動いている oneshot を switch で起動し直すと処理をやり直し、switch も完了を待ち続ける。
    for name, description, kind, start, priority in [
        ("sync", "X のいいねとブックマーク、返信先と引用元を取得して登録する", "oneshot", concat(cli_exe, " sync"), {}),
        ("process", "保存したツイートの OCR と埋め込みを計算する", "oneshot", concat(process, "/bin/xsaved-process"), {"Nice": 19, "IOSchedulingClass": "idle"}),
        ("frames", "動画のフレームを、粗い間隔から順に埋め込み、タグを付ける", "exec", concat(cli_exe, " frames"), {"Nice": 19, "IOSchedulingClass": "idle"}),
    ]:
        service = {"Type": kind, "ExecStartPre": concat(cli_exe, " migrate"), "ExecStart": start}
        service.update(priority)
        home["systemd.user.services.xsaved-" + name] = {
            "Unit": {"Description": description, "OnFailure": failure_notify.on_failure, "X-SwitchMethod": "keep-old"},
            "Service": service,
        }
    home["systemd.user.timers.xsaved-sync"] = {
        "Unit": {"Description": "X のいいねとブックマークを毎時取得する"},
        "Timer": {"OnCalendar": "hourly"},
        "Install": {"WantedBy": ["timers.target"]},
    }
    home["systemd.user.timers.xsaved-process"] = {
        "Unit": {"Description": "OCR と埋め込みを毎晩計算する"},
        "Timer": {"OnCalendar": "*-*-* 04:00:00", "Persistent": True},
        "Install": {"WantedBy": ["timers.target"]},
    }
    server_port = str(port + 1)
    home["systemd.user.sockets.xsaved-web"] = {
        "Unit": {"Description": "保存したツイートの検索の Web UI を待ち受ける"},
        "Socket": {"ListenStream": "127.0.0.1:" + str(port)},
        "Install": {"WantedBy": ["sockets.target"]},
    }
    home["systemd.user.services.xsaved-web"] = {
        "Unit": {"Description": "Web UI への要求を検索のサーバーへ渡す", "BindsTo": ["xsaved-web-server.service"], "After": ["xsaved-web-server.service"]},
        "Service": {"ExecStart": concat(xsaved.systemd, "/lib/systemd/systemd-socket-proxyd --exit-idle-time=15min 127.0.0.1:" + server_port)},
    }
    home["systemd.user.services.xsaved-web-server"] = {
        "Unit": {"Description": "保存したツイートの検索のサーバー", "StopWhenUnneeded": True},
        "Service": {
            "ExecStart": concat(cli_exe, " serve --port " + server_port),
            "ExecStartPost": script("xsaved-web-wait", "until (exec 3<>/dev/tcp/127.0.0.1/" + server_port + ") 2>/dev/null; do sleep 0.5; done\n"),
            "TimeoutStartSec": "5min",
        },
    }
    owner = user.name.replace('"', '""')
    nixos = {
        "services.postgresql.ensureDatabases": [database],
        "services.postgresql.ensureUsers": [{"name": user.name}],
        # 所有者では拡張を作れないので、DB とロールの作成後に superuser で流す。
        "systemd.services.postgresql-setup.script": mkAfter(
            "psql -tAc " + _quote('ALTER DATABASE "' + database + '" OWNER TO "' + owner + '"') + "\n" +
            "psql -d " + _quote(database) + " -tAc 'CREATE EXTENSION IF NOT EXISTS vector; CREATE EXTENSION IF NOT EXISTS pgroonga'\n"),
    }
    return {"home": home, "home_imports": [repoModule("modules/home-manager/xsaved/nixos-only.nix")], "nixos": nixos}
