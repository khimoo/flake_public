# 道具: 画面ロック swaylock。PAM の認証と、暗い見た目の既定（/etc/swaylock/config）を置く。
requires = ["niri_config"]
needs = ["nixos_system"]

_lock = ["swaylock", "-f", "--config", "/etc/swaylock/config"]

def public():
    return {"lock_command": " ".join(_lock)}

def config():
    return {"nixos": {
        "environment.systemPackages": [pkg("swaylock")],
        "security.pam.services.swaylock": {},
        ("environment", "etc", "swaylock/config", "text"): "color=1e1e2e\nshow-failed-attempts\nignore-empty-password\n",
    }}

def writes(niri_config, swayidle):
    return [
        write(niri_config, binds = ['Mod+Alt+L allow-inhibiting=false { spawn ' + " ".join(['"' + arg + '"' for arg in _lock]) + '; }']),
        write(swayidle, lock_command = " ".join(_lock), lock_packages = [pkg("swaylock")]),
    ]
