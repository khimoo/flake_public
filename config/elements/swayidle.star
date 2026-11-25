# 手段: 放置したときの画面ロックと消灯、スリープ前のロック。自動 suspend は、disable_suspend = True を書く element（stay_awake）があると外す。
# 起動は NixOS のユーザーユニットにする。suspend を外すかどうかが accept で届く値によるので、Niri の起動の寄与では組み立てられない。
needs = ["nixos_system"]

def accept(disable_suspend = False):
    return disable_suspend

def config(niri, swaylock, incoming):
    lock = swaylock.lock_command
    off = "niri msg action power-off-monitors"
    # lock ハンドラを置くことで、Vicinae の「Lock Session」など外部ツールが呼ぶ loginctl lock-session でも確実にロックする。
    args = " -w timeout 300 '" + lock + "' timeout 600 '" + off + "' before-sleep '" + lock + "' lock '" + lock + "'"
    if not any([w.value for w in incoming]):
        args += " timeout 1800 'systemctl suspend'"
    return {"nixos": {"systemd.user.services.swayidle": {
        "description": "Idle manager for Wayland",
        "wantedBy": ["graphical-session.target"],
        "partOf": ["graphical-session.target"],
        "after": ["graphical-session.target"],
        "path": [pkg("bash"), pkg("swaylock"), pkg("systemd"), niri.package],
        "unitConfig": {"ConditionEnvironment": "WAYLAND_DISPLAY"},
        "serviceConfig": {
            "ExecStart": concat(exe("swayidle", "swayidle"), args),
            "Restart": "on-failure",
        },
    }}}
