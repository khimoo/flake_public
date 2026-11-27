# 目的: 自分用サーバとして xsaved を公開する。X のいいねとブックマークを集めて保管し、検索の Web UI を動かす（サーバの側。docs/howtouse/xsaved.md）。
def _quote(value):
    return "'" + value.replace("'", "'\"'\"'") + "'"

def _database(value):
    if not value or len(value) > 63 or value[0] not in "abcdefghijklmnopqrstuvwxyz_" or any([c not in "abcdefghijklmnopqrstuvwxyz_0123456789" for c in value.elems()]):
        fail("xsaved: invalid database identifier")
    return value

requires = ["tailnet_gate"]
needs = ["nixos_system"]
role = True

_GPU_LOCK = "/run/xsaved-gpu.lock"
_DEFAULT_PORT = 8765

# ユーザーごとの値は、ホストのファイルのユーザーの表（[[users]] の直後の [users.xsaved]）に書く。
# データと本番用の checkout の場所は、ユーザーのホームから決める。
def public(user):
    values = getattr(user, "xsaved", None)
    if values == None:
        fail("xsaved: user " + user.name + " selects xsaved but has no [users.xsaved] table in the host file")
    port = values.get("web_port", _DEFAULT_PORT)
    if type(port) != "int" or port < 1 or port > 65535:
        fail("xsaved: invalid web port")
    ml_extra = values.get("ml_extra", "ml")
    if ml_extra not in ["ml", "ml-cpu"]:
        fail("xsaved: ml_extra must be ml or ml-cpu")
    data = user.home + "/.local/share/xsaved"
    project = user.home + "/.local/share/xsaved-app"
    database = _database(values.get("database", "xsaved"))
    check_mount = values.get("check_mount", "data_subvolume" in values)
    env = repoPkgWith("packages/xsaved-env", {
        "dataDir": data,
        "database": database,
        "hsaOverrideGfxVersion": values.get("hsa_override", None),
        "checkMount": check_mount,
        "gpuLock": _GPU_LOCK,
        "mlExtra": ml_extra,
    })
    cli = shellAppEnv("xsaved", [env, pkg("util-linux")], {"XSAVED_PROJECT_DIR": project, "XSAVED_ML_EXTRA": ml_extra}, repoText("modules/home-manager/xsaved/xsaved.sh"))
    return {
        "data_dir": data,
        "project_dir": project,
        "database": database,
        "web_port": port,
        "check_mount": check_mount,
        "values": values,
        "gpu_lock": _GPU_LOCK,
        "env": env,
        "cli": cli,
        # メジャー版を上げるとデータディレクトリの移行が要るので、stateVersion に連動させない。
        "postgresql": pkg("postgresql_17"),
        "postgresql_extensions": pkgWithPackages("postgresql_17", ["pgvector", "pgroonga"]),
        "systemd": pkg("systemd"),
    }

def config(host, roles):
    # Web UI の名前（xsaved.home.arpa）は tailnet に 1 つなので、1 台で xsaved を動かすのは 1 人までにする。
    users = [name for name, chosen in roles.hosts.get(host.hostname, {}).items() if "serve_xsaved" in chosen]
    if len(users) > 1:
        fail("xsaved: only one user per host can select serve_xsaved (" + ", ".join(sorted(users)) + ")")
    nixos = {
        "services.postgresql.enable": True,
        "services.postgresql.package": pkg("postgresql_17"),
        "services.postgresql.extensions": pkgSetFn(["pgvector", "pgroonga"]),
        "systemd.tmpfiles.rules": ["f " + _GPU_LOCK + " 0644 root root -"],
    }
    return {"nixos": nixos}

def user_config(user, serve_xsaved, failure_notify, tailnet_web):
    xsaved = serve_xsaved
    database = xsaved.database
    cli = xsaved.cli
    cli_exe = concat(cli, "/bin/xsaved")
    process = shellApp("xsaved-process", [cli, xsaved.systemd], repoText("modules/home-manager/xsaved/process.sh"))
    home = {"home.packages": [xsaved.env, cli]}
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
    owner = user.name.replace('"', '""')
    nixos = {
        "services.postgresql.ensureDatabases": [database],
        "services.postgresql.ensureUsers": [{"name": user.name}],
        # 所有者では拡張を作れないので、DB とロールの作成後に superuser で流す。
        "systemd.services.postgresql-setup.script": mkAfter(
            "psql -tAc " + _quote('ALTER DATABASE "' + database + '" OWNER TO "' + owner + '"') + "\n" +
            "psql -d " + _quote(database) + " -tAc 'CREATE EXTENSION IF NOT EXISTS vector; CREATE EXTENSION IF NOT EXISTS pgroonga'\n"),
    }
    # tailnet の端末からは、門番（tailnet_gate）を通して http://xsaved.home.arpa/ で開く。門番は use_xsaved を選んだホストだけを通す。
    name = tailnet_web.names["serve_xsaved"]
    nixos[("services", "caddy", "virtualHosts", "http://" + name + ":" + str(tailnet_web.gate_port))] = {
        "extraConfig": tailnet_web.gate["serve_xsaved"] + "reverse_proxy 127.0.0.1:" + str(xsaved.web_port) + "\n",
    }
    return {"home": home, "home_imports": [repoModule("modules/home-manager/xsaved/nixos-only.nix")], "nixos": nixos}
