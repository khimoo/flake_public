# 手段: 放置したときの画面ロックと消灯、スリープ前のロック。自動 suspend は、disable_suspend = True を書く element（stay_awake）があると外す。
# ロック実行コマンドと依存パッケージはロッカー側（dms_shell または swaylock）から寄与で受ける。
# 起動は NixOS のユーザーユニットにする。suspend を外すかどうかが accept で届く値によるので、Niri の起動の寄与では組み立てられない。
needs = ["nixos_system"]

def accept(disable_suspend = False, lock_command = "", lock_packages = []):
    return struct(disable_suspend = disable_suspend, lock_command = lock_command, lock_packages = lock_packages)

def config(niri, incoming):
    disable_suspend = False
    lock_commands = []
    lock_packages = []
    for w in incoming:
        v = w.value
        if v.disable_suspend:
            disable_suspend = True
        if v.lock_command and v.lock_command not in lock_commands:
            lock_commands.append(v.lock_command)
        lock_packages += v.lock_packages
    if len(lock_commands) > 1:
        fail("swayidle: multiple lock_command values written: " + ", ".join(lock_commands))
    lock = lock_commands[0] if lock_commands else "loginctl lock-session"
    off = "niri msg action power-off-monitors"
    # lock ハンドラを置くことで、外部ツールや XF86ScreenSaver が呼ぶ loginctl lock-session でも確実にロックする。
    args = " -w timeout 300 '" + lock + "' timeout 600 '" + off + "' before-sleep '" + lock + "' lock '" + lock + "'"
    if not disable_suspend:
        args += " timeout 1800 'systemctl suspend'"
    return {"nixos": {"systemd.user.services.swayidle": {
        "description": "Idle manager for Wayland",
        "wantedBy": ["graphical-session.target"],
        "partOf": ["graphical-session.target"],
        "after": ["graphical-session.target"],
        "path": [pkg("bash"), pkg("systemd"), niri.package] + lock_packages,
        "unitConfig": {"ConditionEnvironment": "WAYLAND_DISPLAY"},
        "serviceConfig": {
            "ExecStart": concat(exe("swayidle", "swayidle"), args),
            "Restart": "on-failure",
        },
    }}}
