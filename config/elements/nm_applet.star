# 道具: NetworkManager のトレイ アプレット。
requires = ["network_manager", "niri_config"]
needs = ["nixos_system"]

def config():
    return {"nixos": {"environment.systemPackages": [pkg("networkmanagerapplet")]}}

def writes(niri_config):
    return [write(niri_config,
        startup = [["nm-applet", "--indicator"]],
        window_rules = ['window-rule {\n    match app-id="^nm-connection-editor$"\n    open-floating true\n}'],
    )]
