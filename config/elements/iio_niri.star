# 目的: 2-in-1 の PC で、センサーに合わせて Niri の画面を回し、タッチとペンの座標を内蔵の画面に合わせる。
# 内蔵の画面の接続名はホストの値 internal_output。
needs = ["nixos_system", "has_orientation_sensor"]

def config(niri, host):
    script_file = file("niri-rotate.py", repoText("modules/home-manager/gui/niri/rotate.py"))
    helper = shellApp(
        "niri-rotate",
        [pkg("python3"), niri.package, pkg("systemd"), pkg("libnotify")],
        concat("exec python3 ", script_file, " '", host.internal_output, '\' "${1:-toggle}"\n'),
    )
    return {"nixos": {
        "services.iio-niri.enable": True,
        "environment.systemPackages": [pkg("brightnessctl"), helper],
    }}

def user_config():
    # Vicinae 等のランチャーから自動回転のオン・オフを呼び出せるようにする。
    return {"home": {
        "xdg.desktopEntries.niri-auto-rotate": {
            "name": "自動回転の切替 (Auto-Rotate Toggle)",
            "comment": "画面の自動回転（iio-niri）をオン・オフする",
            "exec": "niri-rotate toggle",
            "icon": "rotation-locked-symbolic",
            "terminal": False,
            "categories": ["System", "Settings"],
            "settings": {"Keywords": "rotate;rotation;orientation;auto;lock;自動回転;回転;"},
        },
    }}

def writes(niri_config, host):
    return [write(niri_config,
        input = [
            'tablet {\n        map-to-output ' + '"' + host.internal_output + '"\n    }',
            'touch {\n        map-to-output ' + '"' + host.internal_output + '"\n    }',
        ],
        binds = [
            # keyd がキーボードの scale と sleep を、この 2 つのキーに変換している。
            'XF86LaunchA { toggle-overview; }',
            'XF86ScreenSaver allow-inhibiting=false { spawn "loginctl" "lock-session"; }',
            'XF86KbdBrightnessUp allow-when-locked=true { spawn "brightnessctl" "--device=*::kbd_backlight" "set" "+1"; }',
            'XF86KbdBrightnessDown allow-when-locked=true { spawn "brightnessctl" "--device=*::kbd_backlight" "set" "1-"; }',
            # Alt + 更新キーで自動回転をオフにしつつ、画面を時計回りに 90° 回転する。
            # xkeyboard-config の版差で KEY_REFRESH が XF86Reload / XF86Refresh のどちらになっても受ける。
            'Alt+XF86Reload { spawn "niri-rotate" "cw"; }',
            'Alt+XF86Refresh { spawn "niri-rotate" "cw"; }',
        ],
    )]
