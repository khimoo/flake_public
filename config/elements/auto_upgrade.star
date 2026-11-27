# 利用目的: リモート flake の main から毎日自動で nixos-rebuild switch を実行する（docs/howtouse/gce-offload.md）。
needs = ["nixos_system"]

def config(host, owner):
    return {"nixos": {
        "system.autoUpgrade": {
            "enable": True,
            "flake": owner.flake_repo + "#" + host.hostname,
            "dates": "03:00",
            "randomizedDelaySec": "15min",
            "allowReboot": False,
        },
    }}
