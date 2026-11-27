# 目的: xsaved の検索の Web UI を常駐させ、初回の起動待ちをなくす（専用サーバ向け）。
# 常駐プロセスが GPU ロックを握り続けると夜間の埋め込みとバックアップが永久に待つため、検索サーバーではロックを取らない。

def user_config(serve_xsaved, failure_notify):
    port = serve_xsaved.web_port
    cli_exe = concat(serve_xsaved.cli, "/bin/xsaved")
    update = shellAppEnv("xsaved-update", [pkg("git"), pkg("util-linux"), serve_xsaved.systemd, serve_xsaved.cli], {
        "XSAVED_PROJECT_DIR": serve_xsaved.project_dir,
        "XSAVED_WEB_UNIT": "xsaved-web-server.service",
    }, repoText("modules/home-manager/xsaved/update.sh"))
    return {"home": {
        "home.packages": [update],
        "systemd.user.services.xsaved-web-server": {
            "Unit": {"Description": "保存したツイートの検索のサーバー", "OnFailure": failure_notify.on_failure},
            "Service": {
                "Environment": ["XSAVED_NO_GPU_LOCK=1"],
                # OS の postgresql より先にユーザーセッションが立ち上がってもソケット待ちで失敗しないようにする。
                "ExecStartPre": script("xsaved-web-wait-pg", "for _ in $(seq 1 60); do [ -S /run/postgresql/.s.PGSQL.5432 ] && exit 0; sleep 1; done\nexit 1\n"),
                "ExecStart": concat(cli_exe, " serve --port " + str(port) + " --preload"),
                "TimeoutStartSec": "5min",
                "Restart": "on-failure",
                "RestartSec": "5s",
            },
            "Install": {"WantedBy": ["default.target"]},
        },
    }}
