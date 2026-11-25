# 道具: 背景。画像を選ぶ前の既定は単色。
requires = ["niri_config"]
needs = ["nixos_system"]

def config():
    return {"nixos": {"environment.systemPackages": [pkg("swaybg")]}}

def writes(niri_config):
    return [write(niri_config, startup = [["swaybg", "-c", "#1e1e2e"]])]
