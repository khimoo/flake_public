# 目的: 自分用サーバとして xsaved を公開する。X のいいねとブックマークを集めて保管し、検索の Web UI を動かす（サーバの側。docs/howtouse/xsaved.md）。
def _quote(value):
    return "'" + value.replace("'", "'\"'\"'") + "'"

def _database(value):
    if not value or len(value) > 63 or value[0] not in "abcdefghijklmnopqrstuvwxyz_" or any([c not in "abcdefghijklmnopqrstuvwxyz_0123456789" for c in value.elems()]):
        fail("xsaved: invalid database identifier")
    return value

needs = ["nixos_system"]
requires = ["xsaved_data", "xsaved_web_proxy", "xsaved_backup"]

def _settings(host):
    return {
        "users": host.xsaved_users,
        "gpu_lock": "/run/xsaved-gpu.lock",
        # メジャー版を上げるとデータディレクトリの移行が要るので、stateVersion に連動させない。
        "postgresql": pkg("postgresql_17"),
        "postgresql_extensions": pkgWithPackages("postgresql_17", ["pgvector", "pgroonga"]),
        "systemd": pkg("systemd"),
    }

def public(host):
    return _settings(host)

def config(host):
    xsaved = struct(**_settings(host))
    if not xsaved.users:
        fail("xsaved: list the users as [xsaved_users.<user>] in the host file")
    databases = [_database(v.get("database", "xsaved")) for v in xsaved.users.values()]
    if len(databases) != len({name: True for name in databases}):
        fail("xsaved: database names must be unique per user")
    nixos = {
        "services.postgresql.enable": True,
        "services.postgresql.package": xsaved.postgresql,
        "services.postgresql.extensions": pkgSetFn(["pgvector", "pgroonga"]),
        "systemd.tmpfiles.rules": ["f " + xsaved.gpu_lock + " 0644 root root -"],
    }
    return {"nixos": nixos}

def user_config(host, user, failure_notify):
    xsaved = struct(**_settings(host))
    if user.name not in xsaved.users:
        fail("xsaved: user " + user.name + " selects xsaved but the host file has no [xsaved_users." + user.name + "]")
    values = xsaved.users[user.name]
    data = values["data_dir"]
    project = values["project_dir"]
    for path in [data, project]:
        if not path.startswith(user.home + "/"):
            fail("xsaved: data and project paths must live below the user's home")
    database = _database(values.get("database", "xsaved"))
    port = values.get("web_port", 8765)
    if type(port) != "int" or port < 1 or port > 65535:
        fail("xsaved: invalid web port")
    check_mount = values.get("check_mount", False)
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
