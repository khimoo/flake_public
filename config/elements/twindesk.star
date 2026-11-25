requires = ["gui", "bluetooth"]

def _twindesk_pkg():
    return repoPkgWith("packages/twindesk", {"twindesk": inputPkg("twindesk", "default")})

def config():
    return {
        "nixos_imports": [module("twindesk", "nixosModules.default")],
        "nixos": {
            "programs.twindesk.enable": True,
            "programs.twindesk.package": _twindesk_pkg(),
        },
    }

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
