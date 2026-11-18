# 目的: xsaved の検索の Web UI を、ブラウザで開いたときにソケットから起動し、15 分間使われなければ止める（ローカル PC 向け）。
requires = ["xsaved_web_proxy"]

def user_config(serve_xsaved):
    port = serve_xsaved.web_port
    server_port = str(port + 1)
    cli_exe = concat(serve_xsaved.cli, "/bin/xsaved")
    update = shellAppEnv("xsaved-update", [pkg("git"), pkg("util-linux"), serve_xsaved.systemd, serve_xsaved.cli], {
        "XSAVED_PROJECT_DIR": serve_xsaved.project_dir,
        "XSAVED_WEB_UNIT": "xsaved-web.socket",
    }, repoText("modules/home-manager/xsaved/update.sh"))
    return {"home": {
        "home.packages": [update],
        "systemd.user.sockets.xsaved-web": {
            "Unit": {"Description": "保存したツイートの検索の Web UI を待ち受ける"},
            "Socket": {"ListenStream": "127.0.0.1:" + str(port)},
            "Install": {"WantedBy": ["sockets.target"]},
        },
        "systemd.user.services.xsaved-web": {
            "Unit": {"Description": "Web UI への要求を検索のサーバーへ渡す", "BindsTo": ["xsaved-web-server.service"], "After": ["xsaved-web-server.service"]},
            "Service": {"ExecStart": concat(serve_xsaved.systemd, "/lib/systemd/systemd-socket-proxyd --exit-idle-time=15min 127.0.0.1:" + server_port)},
        },
        "systemd.user.services.xsaved-web-server": {
            "Unit": {"Description": "保存したツイートの検索のサーバー", "StopWhenUnneeded": True},
            "Service": {
                "ExecStart": concat(cli_exe, " serve --port " + server_port),
                "ExecStartPost": script("xsaved-web-wait", "until (exec 3<>/dev/tcp/127.0.0.1/" + server_port + ") 2>/dev/null; do sleep 0.5; done\n"),
                "TimeoutStartSec": "5min",
            },
        },
    }}
