# 道具: ディスプレイの配置（kanshi、wdisplays、プロファイル切替ランチャー kanshi-switch）。
# Home Manager ユーザーは ~/.config/kanshi を checkout への live symlink にし、wdisplays の
# "Save to kanshi Config" で保存したプロファイルを即座に反映しつつ Git で宣言的に管理する。
# Home Manager を使わないユーザー（mase）や checkout 未配置時は /etc/kanshi/config へフォールバックする。
# 設計根拠（wdisplays 1.3.0・kanshi 1.8.0 の挙動）は docs/architecture/niri.md を参照。
needs = ["nixos_system"]

_KANSHI_SESSION_SH = """set -euo pipefail
config_home="${XDG_CONFIG_HOME:-${HOME:+$HOME/.config}}"
if [ -n "$config_home" ] && [ -r "$config_home/kanshi/config" ]; then
  exec kanshi --config "$config_home/kanshi/config"
fi
exec kanshi --config /etc/kanshi/config
"""

_KANSHI_SWITCH_DESKTOP = """[Desktop Entry]
Type=Application
Name=ディスプレイ配置の切替 (kanshi)
Comment=kanshi のプロファイル切替・再読み込み・wdisplays 起動
Exec=kanshi-switch
Icon=video-display
Terminal=false
Categories=System;Settings;
Keywords=display;monitor;screen;kanshi;wdisplays;profile;ディスプレイ;モニター;画面;配置;
"""

def config():
    kanshi_session = shellApp("kanshi-session", [pkg("kanshi")], _KANSHI_SESSION_SH)
    switch_script = file("kanshi-switch.py", repoText("modules/home-manager/gui/kanshi-switch.py"))
    kanshi_switch = shellApp(
        "kanshi-switch",
        [pkg("python3"), pkg("kanshi"), pkg("wdisplays"), pkg("fuzzel"), pkg("libnotify")],
        concat("exec python3 ", switch_script, ' "$@"\n'),
    )
    switch_desktop = command(
        "kanshi-switch-desktop",
        concat(
            'mkdir -p "$out/share/applications"\n',
            "cp ",
            file("kanshi-switch.desktop", _KANSHI_SWITCH_DESKTOP),
            ' "$out/share/applications/kanshi-switch.desktop"\n',
        ),
    )
    return {"nixos": {
        "environment.systemPackages": [pkg("kanshi"), pkg("wdisplays"), kanshi_switch, switch_desktop],
        ("environment", "etc", "kanshi/config", "text"): repoText(
            "modules/home-manager/gui/kanshi/config"
        ),
        "systemd.user.services.kanshi": {
            "description": "Dynamic display configuration daemon (kanshi)",
            "wantedBy": ["graphical-session.target"],
            "partOf": ["graphical-session.target"],
            "after": ["graphical-session.target"],
            # profile 内の exec がセッション本来の PATH を引けるようにする。
            "enableDefaultPath": False,
            "unitConfig": {"ConditionEnvironment": "WAYLAND_DISPLAY"},
            "serviceConfig": {
                "ExecStart": concat(kanshi_session, "/bin/kanshi-session"),
                "ExecReload": concat(exe("kanshi", "kanshictl"), " reload"),
                "Restart": "on-failure",
                "RestartSec": 2,
            },
        },
    }}

def user_config(checkout):
    return {"home": {
        # ディレクトリ単位の live symlink。wdisplays 1.3.0 は g_file_set_contents（一時ファイル→rename）で保存する。
        ("xdg", "configFile", "kanshi", "source"): outOfStoreLink(
            checkout.root + "/modules/home-manager/gui/kanshi"
        ),
        # wdisplays 1.3.0 の "Save to kanshi Config" を既定で有効にする。
        "dconf.enable": True,
        "dconf.settings": {
            "network/cycles/wdisplays": {
                "save-kanshi-config": True,
            },
        },
    }}
