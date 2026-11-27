requires = ["gui", "bluetooth"]

def _twindesk_pkg():
    return repoPkgWith("packages/twindesk", {"twindesk": inputPkg("twindesk", "default")})

def config():
    return {
        "nixos_imports": [module("twindesk", "nixosModules.default")],
        "nixos": {
            "programs.twindesk.enable": True,
            "programs.twindesk.package": _twindesk_pkg(),
            # 上流 v3.2.1 の nixosModules.default は services.udev.extraRules に GROUP="input" を書くが、
            # 同じ 99-local.rules の後ろに並ぶ hardware.uinput.enable の GROUP="uinput" に上書きされる。
            # := で最終代入し、setgid input の twindesk-linuxhelper が /dev/uinput を開けるようにする。
            "services.udev.extraRules": 'KERNEL=="uinput", SUBSYSTEM=="misc", GROUP:="input", MODE="0660", OPTIONS+="static_node=uinput"\n',
        },
    }

def writes(keyd):
    # TwinDesk の仮想入力デバイス（linux-helper/src/wl.c）を keyd が掴むと、
    # 注入したクリックが keyd virtual pointer から再出力され、TwinDesk 自身がローカルクリック
    # （takeBack）と誤認して遠隔操作を終了してしまう（キー入力も二重変換になる）ため除外する。
    return [write(keyd, exclude_default_ids = ["1209:7d01", "1209:7d02"])]

def user_config():
    # 上流 autostart.js（#162）に合わせ、標準出力・標準エラーを /dev/null へ逃がして --hidden でトレイ常駐させる。
    # TwinDesk 本体の "Open at login" が書き換える twindesk.desktop と衝突しないよう別名にする。
    launcher = script("twindesk-autostart", concat("exec ", _twindesk_pkg(), "/bin/twindesk --hidden >/dev/null 2>&1\n"))
    return {"home": {
        ("xdg", "configFile", "autostart/twindesk-tray.desktop", "text"): concat(
            "[Desktop Entry]\n",
            "Type=Application\n",
            "Name=TwinDesk\n",
            "Exec=", launcher, "\n",
            "X-GNOME-Autostart-enabled=true\n",
        ),
    }}
